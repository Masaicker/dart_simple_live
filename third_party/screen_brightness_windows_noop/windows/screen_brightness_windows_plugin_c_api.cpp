#include "include/screen_brightness_windows/screen_brightness_windows_plugin_c_api.h"

void ScreenBrightnessWindowsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  // Intentionally do not install method or window-message handlers. The
  // upstream plugin writes the cached monitor brightness on focus changes.
  (void)registrar;
}
