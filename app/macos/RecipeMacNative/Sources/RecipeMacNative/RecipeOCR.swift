import Foundation
import Vision

public enum RecipeOCR {
  public static func privateImage(_ path: String, bundleID: String) -> URL? {
    let manager = FileManager.default
    let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    // path_provider's temporary directory on Mac is Caches/<bundle ID>.
    let roots = [manager.temporaryDirectory] + manager.urls(for: .cachesDirectory, in: .userDomainMask)
      .map { $0.appendingPathComponent(bundleID, isDirectory: true) }
    let inContainer = roots.contains { root in
      let base = root.resolvingSymlinksInPath().path
      let prefix = base.hasSuffix("/") ? base : base + "/"
      return url.path.hasPrefix(prefix)
    }
    guard inContainer, url.lastPathComponent.hasPrefix("ocr-"), url.pathExtension == "png",
          let attributes = try? manager.attributesOfItem(atPath: url.path),
          let size = attributes[.size] as? NSNumber, size.intValue <= 50 * 1024 * 1024
    else { return nil }
    return url
  }

  /// Vision runs locally; the UI dispatches this synchronous work off the main thread.
  public static func recognize(_ url: URL) throws -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    let supported = try request.supportedRecognitionLanguages()
    request.recognitionLanguages = ["ru-RU", "en-US"].filter { supported.contains($0) }
    guard request.recognitionLanguages.contains("ru-RU") else {
      throw RecipeNativeError.runtime("Эта версия macOS не поддерживает русский OCR. Обновите macOS или введите рецепт вручную.")
    }
    let handler = VNImageRequestHandler(url: url)
    try handler.perform([request])
    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
      .joined(separator: "\n")
    guard text.count <= 50000 else {
      throw RecipeNativeError.runtime("Распознанный текст превышает 50 000 символов.")
    }
    return text
  }
}
