#include <gtest/gtest.h>

#include "synthkit_plugin.h"

namespace synthkit {
namespace test {

TEST(SynthKitPlugin, InstantiatesWithoutMethodChannel) {
  SynthKitPlugin plugin;
  SUCCEED();
}

}  // namespace test
}  // namespace synthkit
