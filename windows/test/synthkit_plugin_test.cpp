#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>
#include <windows.h>

#include <memory>
#include <string>
#include <variant>

#include "synthkit_plugin.h"

namespace synthkit {
namespace test {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;

}  // namespace

TEST(SynthKitPlugin, GetBackendName) {
  SynthKitPlugin plugin;
  std::string result_string;
  plugin.HandleMethodCall(
      MethodCall("getBackendName", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          [&result_string](const EncodableValue* result) {
            result_string = std::get<std::string>(*result);
          },
          nullptr, nullptr));

  EXPECT_EQ(result_string, "native-windows");
}

}  // namespace test
}  // namespace synthkit
