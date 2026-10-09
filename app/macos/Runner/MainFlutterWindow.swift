import Cocoa
import FlutterMacOS
import RecipeMacNative

class MainFlutterWindow: NSWindow {
  private var aiChannel: FlutterMethodChannel?
  private var documentsChannel: FlutterMethodChannel?
  private var appearanceChannel: FlutterMethodChannel?
  private var accessibilityObserver: NSObjectProtocol?
  private var activeJob: RecipeModelJob?
  private var activeID: Int?
  private let aiQueue = DispatchQueue(label: "ru.recipevault.local-ai", qos: .userInitiated)

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    flutterViewController.backgroundColor = .clear
    let container = NSViewController()
    container.view = NSView()
    container.addChild(flutterViewController)
    // Sample the desktop through a native material. Regular glass adds soft
    // frosting behind the window without filtering the Flutter content.
    let backdrop = NSVisualEffectView()
    backdrop.material = .underWindowBackground
    backdrop.blendingMode = .behindWindow
    backdrop.state = .active
    if #available(macOS 26.0, *) {
      let glass = NSGlassEffectView()
      glass.style = .regular
      glass.cornerRadius = 16
      glass.contentView = flutterViewController.view
      backdrop.addSubview(glass)
      glass.frame = backdrop.bounds
      glass.autoresizingMask = [.width, .height]
    } else {
      backdrop.addSubview(flutterViewController.view)
      flutterViewController.view.frame = backdrop.bounds
      flutterViewController.view.autoresizingMask = [.width, .height]
    }
    container.view.addSubview(backdrop)
    backdrop.frame = container.view.bounds
    backdrop.autoresizingMask = [.width, .height]
    self.contentViewController = container
    // Keep the native material visible through transparent Flutter surfaces.
    // Do not lower the window alpha: labels and recipe photos stay opaque.
    self.isOpaque = false
    self.backgroundColor = .clear
    self.hasShadow = true
    self.styleMask.insert(.fullSizeContentView)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.title = "Вкуснотека"
    self.minSize = NSSize(width: 720, height: 560)
    self.setContentSize(NSSize(width: 1380, height: 880))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    configureChannels(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  private func configureChannels(_ messenger: FlutterBinaryMessenger) {
    let appearance = FlutterMethodChannel(name: "recipe_vault/appearance", binaryMessenger: messenger)
    appearanceChannel = appearance
    appearance.setMethodCallHandler { [weak self] call, result in
      if call.method == "setBrightness" {
        guard let value = call.arguments as? String,
              value == "light" || value == "dark" else {
          result(FlutterError(code: "invalid_appearance", message: "Некорректная тема.", details: nil))
          return
        }
        self?.appearance = NSAppearance(named: value == "dark" ? .darkAqua : .aqua)
        result(nil)
      } else if call.method == "reduceTransparency" {
        result(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
      } else if call.method == "preferences" {
        result(Self.accessibilityPreferences())
      } else { result(FlutterMethodNotImplemented) }
    }
    accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: nil, queue: .main
    ) { [weak self] _ in
      self?.appearanceChannel?.invokeMethod("accessibilityChanged",
        arguments: Self.accessibilityPreferences())
    }

    let documents = FlutterMethodChannel(name: "recipe_vault/documents", binaryMessenger: messenger)
    documentsChannel = documents
    documents.setMethodCallHandler { call, result in
      guard call.method == "ocr" else { result(FlutterMethodNotImplemented); return }
      guard let data = call.arguments as? [String: Any], let path = data["path"] as? String,
            let bundle = Bundle.main.bundleIdentifier,
            let url = RecipeOCR.privateImage(path, bundleID: bundle) else {
        result(FlutterError(code: "invalid_image", message: "Не удалось открыть изображение.", details: nil)); return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let text = try RecipeOCR.recognize(url)
          DispatchQueue.main.async { result(text) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "ocr_error", message: error.localizedDescription, details: nil))
          }
        }
      }
    }

    let ai = FlutterMethodChannel(name: "recipe_vault/local_ai", binaryMessenger: messenger)
    aiChannel = ai
    ai.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "supported": result(true)
      case "cancel":
        if let data = call.arguments as? [String: Any], data["id"] as? Int == self.activeID {
          self.activeJob?.cancel()
        }
        result(nil)
      case "extract": self.extract(call.arguments, result)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func accessibilityPreferences() -> [String: Bool] {
    ["reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
     "reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion]
  }

  private func extract(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard activeJob == nil else {
      result(FlutterError(code: "busy", message: "Дождитесь текущего разбора.", details: nil)); return
    }
    guard let data = arguments as? [String: Any], let id = data["id"] as? Int,
          let path = data["modelPath"] as? String,
          let instruction = data["instruction"] as? String,
          let template = data["chatTemplate"] as? String,
          let schema = data["schema"] as? String, let fragments = data["fragments"] as? [String],
          let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
          let bundle = Bundle.main.bundleIdentifier else {
      result(FlutterError(code: "invalid_input", message: "Некорректный запрос к ИИ.", details: nil)); return
    }
    let expected = support.appendingPathComponent(bundle)
      .appendingPathComponent("LocalAI/qwen-recipe.litertlm").resolvingSymlinksInPath()
    guard URL(fileURLWithPath: path).resolvingSymlinksInPath() == expected,
          let attributes = try? FileManager.default.attributesOfItem(atPath: expected.path),
          (attributes[.size] as? NSNumber)?.int64Value == 977184032 else {
      result(FlutterError(code: "invalid_model", message: "Скачайте проверенную модель в настройках.", details: nil)); return
    }
    let job = RecipeModelJob()
    let fragmentSchemas = data["fragmentSchemas"] as? [String] ?? []
    activeJob = job
    activeID = id
    aiQueue.async { [weak self] in
      let outcome: Result<[String], Error> = Result {
        try job.extract(modelPath: path, instruction: instruction, chatTemplate: template,
                        schema: schema, fragments: fragments, fragmentSchemas: fragmentSchemas) { text in
          DispatchQueue.main.async {
            self?.aiChannel?.invokeMethod("progress", arguments: ["id": id, "text": text])
          }
        }
      }
      DispatchQueue.main.async {
        self?.activeJob = nil
        self?.activeID = nil
        switch outcome {
        case .success(let outputs): result(["outputs": outputs, "backend": "CPU"])
        case .failure(let error):
          result(FlutterError(code: "local_ai_error", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  deinit {
    activeJob?.cancel()
    if let accessibilityObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
    }
  }
}
