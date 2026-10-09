import Foundation
import CLiteRTLM

public enum RecipeNativeError: LocalizedError {
  case invalidInput, cancelled, runtime(String)
  public var errorDescription: String? {
    switch self {
    case .invalidInput: return "Некорректные данные для локального ИИ."
    case .cancelled: return "Разбор остановлен."
    case .runtime(let message): return message
    }
  }
}

/// One extraction per job. C handles stay on the worker thread, except for the
/// runtime's thread-safe cancellation API, guarded against handle destruction.
public final class RecipeModelJob {
  private let lock = NSLock()
  private var cancelled = false
  private var activeConversation: OpaquePointer?

  public init() {}

  /// The C API wraps this JSON value in a system-role message itself. Passing
  /// {role, content} here nests the message and makes ChatML omit the instruction.
  public static func systemContentJSON(_ instruction: String) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: instruction,
      options: [.fragmentsAllowed]), as: UTF8.self)
  }

  public func cancel() {
    lock.lock()
    cancelled = true
    if let activeConversation {
      litert_lm_conversation_cancel_process(activeConversation)
    }
    lock.unlock()
  }

  private func check() throws {
    lock.lock()
    let stopped = cancelled
    lock.unlock()
    if stopped { throw RecipeNativeError.cancelled }
  }

  private func failure() -> RecipeNativeError {
    let text = litert_lm_get_last_error_message().map { String(cString: $0) }
    litert_lm_clear_last_error()
    return .runtime(text ?? "Не удалось выполнить локальный разбор.")
  }

  public func extract(modelPath: String, instruction: String, chatTemplate: String,
                      schema: String, fragments: [String], fragmentSchemas: [String] = [],
                      progress: (String) -> Void = { _ in }) throws -> [String] {
    guard !fragments.isEmpty, fragments.count <= 64,
          fragments.allSatisfy({ !$0.isEmpty && $0.count <= 10000 }),
          fragments.reduce(0, { $0 + $1.count }) <= 150000,
          instruction.count <= 20000, chatTemplate.count <= 20000,
          schema.count <= 20000,
          (fragmentSchemas.isEmpty || fragmentSchemas.count == fragments.count),
          fragmentSchemas.allSatisfy({ value in
            guard value.count <= 20000, let data = value.data(using: .utf8) else { return false }
            return (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
          }),
          let schemaData = schema.data(using: .utf8),
          (try? JSONSerialization.jsonObject(with: schemaData)) is [String: Any]
    else { throw RecipeNativeError.invalidInput }
    try check()
    guard let settings = litert_lm_engine_settings_create(modelPath, "cpu", nil, nil)
    else { throw failure() }
    defer { litert_lm_engine_settings_delete(settings) }
    litert_lm_engine_settings_set_max_num_tokens(settings, 4096)
    litert_lm_engine_settings_set_num_threads(settings, 4)
    let cache = FileManager.default.temporaryDirectory
      .appendingPathComponent("recipe-lm-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: cache) }
    litert_lm_engine_settings_set_cache_dir(settings, cache.path)
    guard let engine = litert_lm_engine_create(settings) else { throw failure() }
    defer { litert_lm_engine_delete(engine) }
    try check()
    var outputs: [String] = []
    for (index, fragment) in fragments.enumerated() {
      try check()
      progress("Разбираю фрагмент \(index + 1) из \(fragments.count)…")
      outputs.append(try autoreleasepool {
        try extractFragment(engine, instruction, chatTemplate,
          fragmentSchemas.isEmpty ? schema : fragmentSchemas[index], fragment)
      })
    }
    try check()
    return outputs
  }

  private func extractFragment(_ engine: OpaquePointer, _ instruction: String,
                               _ template: String, _ schema: String,
                               _ fragment: String) throws -> String {
    guard let session = litert_lm_session_config_create() else { throw failure() }
    defer { litert_lm_session_config_delete(session) }
    guard let config = litert_lm_conversation_config_create() else { throw failure() }
    defer { litert_lm_conversation_config_delete(config) }
    guard let sampler = litert_lm_sampler_params_create(kLiteRtLmSamplerTypeTopP)
    else { throw failure() }
    defer { litert_lm_sampler_params_delete(sampler) }
    litert_lm_session_config_set_max_output_tokens(session, 1536)
    litert_lm_sampler_params_set_top_k(sampler, 40)
    litert_lm_sampler_params_set_top_p(sampler, 1)
    litert_lm_sampler_params_set_temperature(sampler, 0)
    litert_lm_session_config_set_sampler_params(session, sampler)
    litert_lm_conversation_config_set_session_config(config, session)
    let system = try Self.systemContentJSON(instruction)
    litert_lm_conversation_config_set_system_message(config, system)
    litert_lm_conversation_config_set_prompt_template(config, template)
    var provider = kLiteRtLmConstraintProviderTypeLlGuidance
    litert_lm_conversation_config_set_constraint_provider(config, &provider)
    litert_lm_conversation_config_set_enable_constrained_decoding(config, true)
    guard let conversation = litert_lm_conversation_create(engine, config)
    else { throw failure() }
    lock.lock()
    activeConversation = conversation
    if cancelled { litert_lm_conversation_cancel_process(conversation) }
    lock.unlock()
    defer {
      lock.lock()
      activeConversation = nil
      litert_lm_conversation_delete(conversation)
      lock.unlock()
    }
    try check()
    guard let args = litert_lm_conversation_optional_args_create() else { throw failure() }
    defer { litert_lm_conversation_optional_args_delete(args) }
    litert_lm_conversation_optional_args_set_constraint(args, kLiteRtLmConstraintTypeJsonSchema, schema)
    let user = try json(["role": "user", "content": "Источник рецепта:\n" + fragment])
    guard let response = litert_lm_conversation_send_message(conversation, user, nil, args)
    else { try check(); throw failure() }
    defer { litert_lm_json_response_delete(response) }
    try check()
    guard let pointer = litert_lm_json_response_get_string(response),
          let data = String(cString: pointer).data(using: .utf8),
          let message = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw RecipeNativeError.runtime("ИИ вернул нечитаемый ответ.") }
    if let content = message["content"] as? String { return content }
    if let blocks = message["content"] as? [[String: Any]] {
      return blocks.compactMap { $0["text"] as? String }.joined()
    }
    throw RecipeNativeError.runtime("В ответе ИИ нет текста рецепта.")
  }

  private func json(_ value: [String: String]) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
  }
}
