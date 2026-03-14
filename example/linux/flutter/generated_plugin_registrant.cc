//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <synthkit/synth_kit_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) synthkit_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "SynthKitPlugin");
  synth_kit_plugin_register_with_registrar(synthkit_registrar);
}
