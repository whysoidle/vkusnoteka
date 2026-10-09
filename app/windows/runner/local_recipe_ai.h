#ifndef RUNNER_LOCAL_RECIPE_AI_H_
#define RUNNER_LOCAL_RECIPE_AI_H_
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>
#include "ai_process.h"

class LocalRecipeAi {
 public:
  explicit LocalRecipeAi(flutter::BinaryMessenger* messenger);
  ~LocalRecipeAi();
 private:
  AiProcess process_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
#endif
