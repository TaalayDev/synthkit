#ifndef FLUTTER_PLUGIN_SYNTHKIT_PLUGIN_H_
#define FLUTTER_PLUGIN_SYNTHKIT_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace synthkit {

class WindowsSynthKitEngine;

class SynthKitPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  SynthKitPlugin();

  virtual ~SynthKitPlugin();

  // Disallow copy and assign.
  SynthKitPlugin(const SynthKitPlugin&) = delete;
  SynthKitPlugin& operator=(const SynthKitPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  std::unique_ptr<WindowsSynthKitEngine> engine_;
};

}  // namespace synthkit

#endif  // FLUTTER_PLUGIN_SYNTHKIT_PLUGIN_H_
