#include "../ai_process.h"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <cstdlib>

namespace {
void Require(bool condition, const char* message) {
  if (!condition) { std::cerr << message << std::endl; std::exit(1); }
}
}
int wmain(int argc, wchar_t* argv[]) {
  if (argc == 4 && std::wstring(argv[1]) == L"--child") {
    std::ofstream output(std::filesystem::path(argv[2]), std::ios::binary);
    const DWORD pid = GetCurrentProcessId();
    output.write(reinterpret_cast<const char*>(&pid), sizeof(pid));
    const std::wstring text(argv[3]);
    output.write(reinterpret_cast<const char*>(text.data()),
                 static_cast<std::streamsize>(text.size() * sizeof(wchar_t)));
    output.close();
    Sleep(INFINITE);
    return 0;
  }
  wchar_t executable[MAX_PATH], directory[MAX_PATH];
  Require(GetModuleFileNameW(nullptr, executable, MAX_PATH) > 0, "executable");
  Require(GetTempPathW(MAX_PATH, directory) > 0, "temporary directory");
  const auto file = std::filesystem::path(directory) /
      (L"vkusnoteka-ai-" + std::to_wstring(GetCurrentProcessId()) + L".bin");
  const std::wstring argument = L"Рецепт с пробелами \\\"цитата\\\" и путь C:\\ИИ\\";
  DWORD before = 0, after = 0;
  Require(GetProcessHandleCount(GetCurrentProcess(), &before) != 0, "handle count");
  for (int64_t id = 1; id <= 12; ++id) {
    HANDLE child = nullptr;
    {
      AiProcess process;
      Require(process.Start(executable, {L"--child", file.wstring(), argument}, id), "start");
      Require(process.Running(id), "running");
      for (int retry = 0; retry < 500; ++retry) {
        if (std::filesystem::exists(file) && std::filesystem::file_size(file) >= sizeof(DWORD) + argument.size() * sizeof(wchar_t)) break;
        Sleep(10);
      }
      std::ifstream input(file, std::ios::binary);
      DWORD pid = 0;
      input.read(reinterpret_cast<char*>(&pid), sizeof(pid));
      std::wstring text(argument.size(), L'\0');
      input.read(reinterpret_cast<char*>(text.data()), static_cast<std::streamsize>(text.size() * sizeof(wchar_t)));
      Require(text == argument, "UTF-16 paths, quotes and trailing backslashes");
      child = OpenProcess(SYNCHRONIZE, FALSE, pid);
      Require(child != nullptr, "open child");
      process.Stop(id + 1);
      Require(process.Running(id), "stale cancellation must not kill another import");
      if (id % 2 == 0) process.Stop(id);
      // Odd iterations verify destructor cleanup; even ones explicit cancel.
    }
    Require(WaitForSingleObject(child, 5000) == WAIT_OBJECT_0, "worker must die");
    CloseHandle(child);
    std::filesystem::remove(file);
  }
  Require(GetProcessHandleCount(GetCurrentProcess(), &after) != 0, "final handle count");
  Require(after <= before, "native process or job handles leaked");
  std::cout << "Windows AI: Unicode arguments, cancellation, destruction and 12 lifecycle cycles passed" << std::endl;
}
