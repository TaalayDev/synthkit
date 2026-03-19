#ifndef FLUTTER_PLUGIN_SYNTHKIT_PLUGIN_H_
#define FLUTTER_PLUGIN_SYNTHKIT_PLUGIN_H_

#include <flutter/plugin_registrar_windows.h>

namespace synthkit {

class SynthKitPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  SynthKitPlugin();

  virtual ~SynthKitPlugin();

  // Disallow copy and assign.
  SynthKitPlugin(const SynthKitPlugin&) = delete;
  SynthKitPlugin& operator=(const SynthKitPlugin&) = delete;
};

}  // namespace synthkit

#endif  // FLUTTER_PLUGIN_SYNTHKIT_PLUGIN_H_
