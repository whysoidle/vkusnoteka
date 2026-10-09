#ifndef RUNNER_AI_PROCESS_H_
#define RUNNER_AI_PROCESS_H_

#include <windows.h>
#include <cstdint>
#include <string>
#include <vector>

// Owns a suspended-then-assigned child: it can never outlive its Job Object.
class AiProcess {
 public:
  ~AiProcess() { Stop(); }
  bool Start(const std::wstring& executable,
             const std::vector<std::wstring>& arguments, int64_t id);
  void Stop();
  void Stop(int64_t id) { if (id == id_) Stop(); }
  bool Running(int64_t id) const;
  static std::wstring Quote(const std::wstring& argument);

 private:
  HANDLE job_ = nullptr;
  HANDLE process_ = nullptr;
  int64_t id_ = 0;
};
#endif
