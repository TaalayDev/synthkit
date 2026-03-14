#include "include/synthkit/synthkit_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "synthkit_plugin.h"

void SynthKitPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  synthkit::SynthKitPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
