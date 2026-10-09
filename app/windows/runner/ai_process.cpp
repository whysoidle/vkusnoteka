#include "ai_process.h"

std::wstring AiProcess::Quote(const std::wstring& argument) {
  std::wstring result = L"\"";
  size_t slashes = 0;
  for (const wchar_t c : argument) {
    if (c == L'\\') {
      ++slashes;
    } else {
      result.append(slashes * (c == L'"' ? 2 : 1), L'\\');
      if (c == L'"') result += L'\\';
      result += c;
      slashes = 0;
    }
  }
  result.append(slashes * 2, L'\\');
  return result + L'"';
}

bool AiProcess::Start(const std::wstring& executable,
                      const std::vector<std::wstring>& arguments, int64_t id) {
  if (Running(id_)) return false;
  Stop();
  job_ = CreateJobObjectW(nullptr, nullptr);
  if (!job_) return false;
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!SetInformationJobObject(job_, JobObjectExtendedLimitInformation,
                               &limits, sizeof(limits))) {
    Stop();
    return false;
  }
  std::wstring command = Quote(executable);
  for (const auto& argument : arguments) command += L" " + Quote(argument);
  const auto directory = executable.substr(0, executable.find_last_of(L"\\/"));
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION child{};
  if (!CreateProcessW(executable.c_str(), command.data(), nullptr, nullptr,
                       FALSE, CREATE_SUSPENDED | CREATE_NO_WINDOW,
                       nullptr, directory.c_str(), &startup, &child)) {
    Stop();
    return false;
  }
  process_ = child.hProcess;
  id_ = id;
  if (!AssignProcessToJobObject(job_, process_) ||
      ResumeThread(child.hThread) == static_cast<DWORD>(-1)) {
    TerminateProcess(process_, 1);
    CloseHandle(child.hThread);
    Stop();
    return false;
  }
  CloseHandle(child.hThread);
  return true;
}

bool AiProcess::Running(int64_t id) const {
  return id == id_ && process_ &&
         WaitForSingleObject(process_, 0) == WAIT_TIMEOUT;
}

void AiProcess::Stop() {
  if (job_) {
    // Explicit termination also works when Windows duplicates a job handle.
    TerminateJobObject(job_, 0);
    CloseHandle(job_);
    job_ = nullptr;
  }
  if (process_) {
    CloseHandle(process_);
    process_ = nullptr;
  }
  id_ = 0;
}
