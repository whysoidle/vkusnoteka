#include "local_recipe_ai.h"
#include <flutter/standard_method_codec.h>
#include <variant>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;

std::wstring Wide(const std::string& text) {
  if (text.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                      text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                      static_cast<int>(text.size()), result.data(), size);
  return result;
}
std::wstring Executable() {
  std::wstring path(32768, L'\0');
  const DWORD size = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (!size || size == path.size()) return {};
  path.resize(size);
  return path.substr(0, path.find_last_of(L"\\/")) + L"\\LocalAI\\llama-server.exe";
}
const Value* Get(const Map& map, const char* key) {
  const auto found = map.find(Value(key));
  return found == map.end() ? nullptr : &found->second;
}
int64_t Integer(const Map& map, const char* key, int64_t fallback = 0) {
  const auto* value = Get(map, key);
  if (!value) return fallback;
  if (const auto* n = std::get_if<int32_t>(value)) return *n;
  if (const auto* n = std::get_if<int64_t>(value)) return *n;
  return fallback;
}
std::string String(const Map& map, const char* key) {
  const auto* value = Get(map, key);
  if (!value) return {};
  const auto* text = std::get_if<std::string>(value);
  return text ? *text : std::string();
}
bool Exists(const std::wstring& path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  return !path.empty() && attributes != INVALID_FILE_ATTRIBUTES &&
         !(attributes & FILE_ATTRIBUTE_DIRECTORY);
}
}

LocalRecipeAi::LocalRecipeAi(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "recipe_vault/local_ai", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "supported") {
      result->Success(Value(Exists(Executable())));
      return;
    }
    const auto* map = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
    if (!map) { result->Error("arguments", "Invalid AI request"); return; }
    const int64_t id = Integer(*map, "id");
    if (call.method_name() == "stop") {
      process_.Stop(id);
      result->Success();
    } else if (call.method_name() == "running") {
      result->Success(Value(process_.Running(id)));
    } else if (call.method_name() == "start") {
      const auto model = Wide(String(*map, "modelPath"));
      const auto key = Wide(String(*map, "key"));
      const auto port = Integer(*map, "port");
      const auto threads = Integer(*map, "threads", 4);
      if (id <= 0 || !Exists(model) || key.size() != 64 || port < 1024 ||
          port > 65535 || threads < 1 || threads > 8) {
        result->Error("arguments", "Invalid model or runtime parameters");
        return;
      }
      if (!process_.Start(Executable(), {
          L"--model", model, L"--host", L"127.0.0.1", L"--port", std::to_wstring(port),
          L"--api-key", key, L"--ctx-size", L"8192", L"--parallel", L"1",
          L"--threads", std::to_wstring(threads), L"--gpu-layers", L"0",
          L"--batch-size", L"512", L"--ubatch-size", L"128",
          L"--no-webui", L"--no-context-shift", L"--offline", L"--log-disable"}, id)) {
        result->Error("start", "Не удалось запустить локальный ИИ. Проверьте установку и свободную память.");
        return;
      }
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
}
LocalRecipeAi::~LocalRecipeAi() {
  channel_->SetMethodCallHandler(nullptr);
  process_.Stop();
}
