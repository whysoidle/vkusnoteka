import Cocoa
import FlutterMacOS
import XCTest
import Security
import RecipeMacNative

class RunnerTests: XCTestCase {

  func testLiteRTSystemContentIsNotWrappedInAnotherRoleMessage() throws {
    let instruction = "Извлеки рецепт.\nНе добавляй продукты. \"Цитата\""
    let content = try RecipeModelJob.systemContentJSON(instruction)
    let decoded = try JSONSerialization.jsonObject(with: Data(content.utf8),
      options: [.fragmentsAllowed])
    XCTAssertEqual(decoded as? String, instruction)
    XCTAssertFalse(decoded is [String: Any])
  }

  func testFragmentSchemaCountIsCheckedBeforeOpeningModel() {
    XCTAssertThrowsError(try RecipeModelJob().extract(
      modelPath: "/nonexistent/test-model", instruction: "", chatTemplate: "",
      schema: "{}", fragments: ["Тест"], fragmentSchemas: ["{}", "{}"])) { error in
      guard let native = error as? RecipeNativeError else {
        return XCTFail("Expected invalid input before loading the model")
      }
      guard case .invalidInput = native else {
        return XCTFail("Expected invalid input before loading the model")
      }
    }
  }

  func testPersonalBuildCanRoundTripLoginKeychain() {
    // Only this unique synthetic fixture is touched; no saved user passwords.
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "ru.recipevault.validation",
      kSecAttrAccount as String: UUID().uuidString,
    ]
    let value = Data("WebDAV-test-Русский".utf8)
    var write = query
    write[kSecValueData as String] = value
    XCTAssertEqual(SecItemAdd(write as CFDictionary, nil), errSecSuccess)
    defer { SecItemDelete(query as CFDictionary) }
    var read = query
    read[kSecReturnData as String] = true
    read[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    XCTAssertEqual(SecItemCopyMatching(read as CFDictionary, &result), errSecSuccess)
    XCTAssertEqual(result as? Data, value)
  }

  @MainActor
  func testNativeWindowContainsFlutterAndKeepsTrafficLights() {
    let window = NSApplication.shared.windows.first { $0.title == "Вкуснотека" }
    XCTAssertNotNil(window)
    XCTAssertNotNil(window?.standardWindowButton(.closeButton))
    XCTAssertEqual(window?.minSize.width, 720)
    XCTAssertTrue(window?.contentViewController?.children.contains {
      $0 is FlutterViewController
    } ?? false)
  }

  @MainActor
  func testRussianOCRInsideApplicationSandbox() throws {
    let bitmap = try XCTUnwrap(NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 1600, pixelsHigh: 900,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 1600, height: 900).fill()
    let text: NSString = "Сырники\nТворог — 400 г\nМука — 3 столовые ложки\nСмешайте ингредиенты."
    text.draw(in: NSRect(x: 80, y: 80, width: 1400, height: 740), withAttributes: [
      .font: NSFont.systemFont(ofSize: 56), .foregroundColor: NSColor.black,
    ])
    NSGraphicsContext.restoreGraphicsState()
    let bundle = try XCTUnwrap(Bundle.main.bundleIdentifier)
    let cache = try XCTUnwrap(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
      .appendingPathComponent(bundle, isDirectory: true)
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    let url = cache.appendingPathComponent("ocr-test-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: url) }
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    let allowed = try XCTUnwrap(RecipeOCR.privateImage(url.path, bundleID: bundle))
    XCTAssertNil(RecipeOCR.privateImage("/etc/hosts", bundleID: bundle))
    let recognized = try RecipeOCR.recognize(allowed)
    XCTAssertTrue(recognized.contains("Сырники"))
    XCTAssertTrue(recognized.contains("400"))
    XCTAssertTrue(recognized.contains("Смешайте"))
  }

}
