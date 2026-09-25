#include "flutter_window.h"

#include <optional>
#include <string>
#include <utility>

#include <commctrl.h>
#include <imm.h>
#include <msctf.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

std::string CurrentKeyboardLayoutName() {
  wchar_t layout_name[KL_NAMELENGTH] = {};
  return GetKeyboardLayoutNameW(layout_name)
             ? Utf8FromUtf16(layout_name)
             : "unknown";
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // Capture the stock window style once while the caption is guaranteed to be
  // present. Fullscreen and small-window modes mutate the style afterwards;
  // restoring from this baseline keeps the title bar from being lost.
  windowed_style_ = GetWindowLongPtr(GetHandle(), GWL_STYLE);
  windowed_ex_style_ = GetWindowLongPtr(GetHandle(), GWL_EXSTYLE);

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  shortcut_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "simple_live/desktop_shortcuts",
          &flutter::StandardMethodCodec::GetInstance());
  shortcut_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setShortcutCaptureEnabled") {
          const auto* arguments =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments) {
            const auto enabled = arguments->find(
                flutter::EncodableValue("enabled"));
            if (enabled != arguments->end()) {
              if (const auto* value =
                      std::get_if<bool>(&enabled->second)) {
                shortcut_capture_enabled_ = *value;
              }
            }
          }
          result->Success();
          return;
        }
        if (call.method_name() == "inputStateSnapshot") {
          result->Success(flutter::EncodableValue(CurrentInputState(true)));
          return;
        }
        if (call.method_name() == "setImeDiagnosticsEnabled") {
          if (const auto* enabled = std::get_if<bool>(call.arguments())) {
            ime_diagnostics_enabled_ = *enabled;
          }
          result->Success();
          return;
        }
        result->NotImplemented();
      });
  ConfigureWindowChromeChannel();
  const HWND flutter_view = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(flutter_view);
  if (GetWindowThreadProcessId(flutter_view, nullptr) == GetCurrentThreadId()) {
    flutter_view_subclass_installed_ =
        SetWindowSubclass(flutter_view, FlutterViewSubclassProc, 1,
                          reinterpret_cast<DWORD_PTR>(this)) != FALSE;
  }

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::ConfigureWindowChromeChannel() {
  window_chrome_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "simple_live/windows_chrome",
          &flutter::StandardMethodCodec::GetInstance());
  window_chrome_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "apply") {
          ApplyFullscreenChrome();
          result->Success();
          return;
        }
        if (call.method_name() == "restore") {
          RestoreWindowChrome();
          result->Success();
          return;
        }
        result->NotImplemented();
      });
}

void FlutterWindow::ApplyFullscreenChrome() {
  HWND hwnd = GetHandle();
  if (!hwnd) return;
  // Only refresh the saved baseline from a captioned (normal windowed) state;
  // saving while the caption is hidden (small-window mode) would make every
  // later restore drop the title bar.
  if (!fullscreen_chrome_applied_) {
    const auto current_style = GetWindowLongPtr(hwnd, GWL_STYLE);
    if (current_style & WS_CAPTION) {
      windowed_style_ = current_style;
      windowed_ex_style_ = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
    }
  }
  const auto style = windowed_style_ &
      ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZE | WS_MAXIMIZE | WS_SYSMENU);
  SetWindowLongPtr(hwnd, GWL_STYLE, style);
  SetWindowLongPtr(hwnd, GWL_EXSTYLE,
                   windowed_ex_style_ & ~WS_EX_DLGMODALFRAME);
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
  fullscreen_chrome_applied_ = true;
}

void FlutterWindow::RestoreWindowChrome() {
  HWND hwnd = GetHandle();
  if (!hwnd || !fullscreen_chrome_applied_) return;
  SetWindowLongPtr(hwnd, GWL_STYLE, windowed_style_);
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, windowed_ex_style_);
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
  fullscreen_chrome_applied_ = false;
}

void FlutterWindow::OnDestroy() {
  if (flutter_view_subclass_installed_ && flutter_controller_) {
    RemoveWindowSubclass(flutter_controller_->view()->GetNativeWindow(),
                         FlutterViewSubclassProc, 1);
    flutter_view_subclass_installed_ = false;
  }
  shortcut_channel_.reset();
  window_chrome_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

unsigned long long CurrentUnixMilliseconds() {
  FILETIME file_time = {};
  GetSystemTimeAsFileTime(&file_time);
  ULARGE_INTEGER ticks = {};
  ticks.LowPart = file_time.dwLowDateTime;
  ticks.HighPart = file_time.dwHighDateTime;
  return (ticks.QuadPart - 116444736000000000ULL) / 10000ULL;
}

static std::string GuidString(const GUID& guid) {
  wchar_t buffer[39] = {};
  return StringFromGUID2(guid, buffer, 39) > 0
             ? Utf8FromUtf16(buffer)
             : "unknown";
}

static std::string CurrentTsfProfile() {
  ITfInputProcessorProfileMgr* manager = nullptr;
  const HRESULT create_result = CoCreateInstance(
      CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
      IID_ITfInputProcessorProfileMgr,
      reinterpret_cast<void**>(&manager));
  if (FAILED(create_result) || !manager) {
    return "tsfProfile=unavailable hr=" +
           std::to_string(static_cast<unsigned long>(create_result));
  }
  TF_INPUTPROCESSORPROFILE profile = {};
  const HRESULT profile_result =
      manager->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD, &profile);
  manager->Release();
  if (FAILED(profile_result)) {
    return "tsfProfile=unavailable hr=" +
           std::to_string(static_cast<unsigned long>(profile_result));
  }
  return "tsfType=" + std::to_string(profile.dwProfileType) +
         " tsfLang=" + std::to_string(profile.langid) +
         " tsfClass=" + GuidString(profile.clsid) +
         " tsfProfile=" + GuidString(profile.guidProfile);
}

std::string FlutterWindow::CurrentInputState(bool include_tsf_profile) {
  std::string state = "layout=" + CurrentKeyboardLayoutName();
  state += flutter_view_subclass_installed_ ? " viewHook=true"
                                            : " viewHook=false";
  state += shortcut_capture_enabled_ ? " shortcutCapture=true"
                                     : " shortcutCapture=false";
  if (include_tsf_profile) {
    state += " " + CurrentTsfProfile();
  }
  const HWND focused = GetFocus();
  if (!focused) {
    return state + " focus=none";
  }
  const HWND flutter_view =
      flutter_controller_ ? flutter_controller_->view()->GetNativeWindow()
                          : nullptr;
  state += focused == flutter_view ? " focus=flutterView"
           : focused == GetHandle() ? " focus=runner"
                                    : " focus=other";
  const HIMC ime_context = ImmGetContext(focused);
  if (!ime_context) {
    return state + " imeContext=none";
  }
  state += ImmGetOpenStatus(ime_context) ? " immOpen=true" : " immOpen=false";
  DWORD conversion = 0;
  DWORD sentence = 0;
  if (ImmGetConversionStatus(ime_context, &conversion, &sentence)) {
    state += (conversion & IME_CMODE_NATIVE) ? " immNativeMode=true"
                                             : " immNativeMode=false";
    state += " immConversion=" + std::to_string(conversion);
    state += " immSentence=" + std::to_string(sentence);
  } else {
    state += " immNativeMode=unknown";
  }
  ImmReleaseContext(focused, ime_context);
  return state;
}

LRESULT CALLBACK FlutterWindow::FlutterViewSubclassProc(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam,
    UINT_PTR subclass_id, DWORD_PTR reference_data) {
  (void)subclass_id;
  auto* window = reinterpret_cast<FlutterWindow*>(reference_data);
  if (window) {
    window->LogFlutterViewMessage(message, wparam, lparam);
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

void FlutterWindow::LogFlutterViewMessage(UINT message, WPARAM wparam,
                                          LPARAM lparam) {
  if (!ime_diagnostics_enabled_ || !shortcut_channel_) {
    return;
  }
  std::string event;
  switch (message) {
    case WM_KEYDOWN:
    case WM_SYSKEYDOWN:
      if (wparam == VK_F4 && (GetKeyState(VK_CONTROL) & 0x8000)) {
        event = "Ctrl+F4 keydown";
      } else if ((wparam >= 'A' && wparam <= 'Z') ||
                 (wparam >= '0' && wparam <= '9')) {
        event = "printable keydown";
      }
      break;
    case WM_CHAR:
    case WM_UNICHAR:
      event = "character message";
      break;
    case WM_SETFOCUS:
      event = "WM_SETFOCUS";
      break;
    case WM_KILLFOCUS:
      event = "WM_KILLFOCUS";
      break;
    case WM_INPUTLANGCHANGE:
      event = "WM_INPUTLANGCHANGE";
      break;
    case WM_INPUTLANGCHANGEREQUEST:
      event = "WM_INPUTLANGCHANGEREQUEST";
      break;
    case WM_IME_SETCONTEXT:
      event = wparam ? "WM_IME_SETCONTEXT active" : "WM_IME_SETCONTEXT inactive";
      break;
    case WM_IME_STARTCOMPOSITION:
      event = "WM_IME_STARTCOMPOSITION";
      break;
    case WM_IME_COMPOSITION:
      event = "WM_IME_COMPOSITION";
      if (lparam & GCS_COMPSTR) event += " composing";
      if (lparam & GCS_RESULTSTR) event += " result";
      break;
    case WM_IME_ENDCOMPOSITION:
      event = "WM_IME_ENDCOMPOSITION";
      break;
    case WM_IME_CHAR:
      event = "WM_IME_CHAR";
      break;
    case WM_IME_KEYDOWN:
      event = "WM_IME_KEYDOWN";
      break;
    case WM_IME_KEYUP:
      event = "WM_IME_KEYUP";
      break;
    case WM_IME_REQUEST:
      event = "WM_IME_REQUEST";
      break;
    case WM_IME_NOTIFY:
      if (wparam == IMN_SETOPENSTATUS) {
        event = "IMN_SETOPENSTATUS";
      } else if (wparam == IMN_SETCONVERSIONMODE) {
        event = "IMN_SETCONVERSIONMODE";
      } else if (wparam == IMN_OPENCANDIDATE) {
        event = "IMN_OPENCANDIDATE";
      } else if (wparam == IMN_CLOSECANDIDATE) {
        event = "IMN_CLOSECANDIDATE";
      }
      break;
    default:
      return;
  }
  if (event.empty()) {
    return;
  }
  shortcut_channel_->InvokeMethod(
      "imeWindowMessage",
      std::make_unique<flutter::EncodableValue>(
          event + " nativeMs=" + std::to_string(CurrentUnixMilliseconds()) +
          " layout=" + CurrentKeyboardLayoutName()));
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  switch (message) {
    case WM_KEYDOWN:
    case WM_SYSKEYDOWN:
      if (HandleShortcutKeyDown(wparam, lparam)) {
        return 0;
      }
      break;
    case WM_INPUTLANGCHANGE:
      if (shortcut_channel_) {
        shortcut_channel_->InvokeMethod(
            "inputLanguageChanged",
            std::make_unique<flutter::EncodableValue>(
                CurrentKeyboardLayoutName()));
      }
      break;
    case WM_INPUTLANGCHANGEREQUEST:
      if (ime_diagnostics_enabled_ && shortcut_channel_) {
        shortcut_channel_->InvokeMethod(
            "imeWindowMessage",
            std::make_unique<flutter::EncodableValue>(
                "top-level WM_INPUTLANGCHANGEREQUEST"));
      }
      break;
    case WM_ACTIVATE:
      if (LOWORD(wparam) != WA_INACTIVE && shortcut_channel_) {
        shortcut_channel_->InvokeMethod(
            "inputLanguageSnapshot",
            std::make_unique<flutter::EncodableValue>(
                CurrentKeyboardLayoutName()));
      }
      break;
    default:
      break;
  }

  // Give Flutter, including plugins and IMEs, an opportunity to handle window
  // messages after desktop shortcut keys have been detected by physical key.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

bool FlutterWindow::HandleShortcutKeyDown(WPARAM wparam, LPARAM lparam) {
  // When an editable control has focus, leave every key message to Flutter
  // and the active IME. The Dart side keeps this capture flag in sync.
  if (!shortcut_capture_enabled_) {
    return false;
  }
  // Win+Space belongs to Windows input-method switching, not player shortcuts.
  if ((GetKeyState(VK_LWIN) & 0x8000) ||
      (GetKeyState(VK_RWIN) & 0x8000)) {
    return false;
  }
  const std::string key = ShortcutKeyForWindowsKey(wparam, lparam);
  if (key.empty()) {
    return false;
  }
  SendShortcutEvent(key);
  return true;
}

std::string FlutterWindow::ShortcutKeyForWindowsKey(WPARAM wparam,
                                                     LPARAM lparam) {
  const UINT scan_code = (lparam >> 16) & 0xff;
  switch (scan_code) {
    case 0x21:
      return "keyF";
    case 0x20:
      return "keyD";
    case 0x32:
      return "keyM";
    case 0x13:
      return "keyR";
    case 0x2e:
      return "keyC";
    case 0x10:
      return "keyQ";
    case 0x12:
      return "keyE";
    case 0x14:
      return "keyT";
    case 0x22:
      return "keyG";
    case 0x30:
      return "keyB";
    case 0x31:
      return "keyN";
    case 0x48:
      return "arrowUp";
    case 0x50:
      return "arrowDown";
    case 0x39:
      return "keySpace";
    default:
      break;
  }

  switch (wparam) {
    case 'F':
      return "keyF";
    case 'D':
      return "keyD";
    case 'M':
      return "keyM";
    case 'R':
      return "keyR";
    case 'C':
      return "keyC";
    case 'Q':
      return "keyQ";
    case 'E':
      return "keyE";
    case 'T':
      return "keyT";
    case 'G':
      return "keyG";
    case 'B':
      return "keyB";
    case 'N':
      return "keyN";
    case VK_SPACE:
      return "keySpace";
    case VK_UP:
      return "arrowUp";
    case VK_DOWN:
      return "arrowDown";
    default:
      return "";
  }
}

bool FlutterWindow::SendShortcutEvent(const std::string& key) {
  if (!shortcut_channel_) {
    return false;
  }
  flutter::EncodableMap arguments = {
      {flutter::EncodableValue("key"), flutter::EncodableValue(key)},
  };
  shortcut_channel_->InvokeMethod(
      "shortcutKeyDown",
      std::make_unique<flutter::EncodableValue>(arguments));
  return false;
}
