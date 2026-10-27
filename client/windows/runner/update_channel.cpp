#include "update_channel.h"
#include "update_files.h"
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <regex>

using namespace app_update;
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
static std::string Text(const Map& args, const char* key) {
  const auto value = args.find(Value(key));
  if (value == args.end() || !std::holds_alternative<std::string>(value->second)) throw std::runtime_error("identity");
  return std::get<std::string>(value->second);
}
static int64_t Number(const Map& args, const char* key) {
  const auto value = args.find(Value(key));
  if (value == args.end()) throw std::runtime_error("identity");
  if (const auto* n = std::get_if<int64_t>(&value->second)) return *n;
  if (const auto* n = std::get_if<int32_t>(&value->second)) return *n;
  throw std::runtime_error("identity");
}
static std::string Version() { return std::to_string(FLUTTER_VERSION_MAJOR) + "." + std::to_string(FLUTTER_VERSION_MINOR) + "." + std::to_string(FLUTTER_VERSION_PATCH); }
std::unique_ptr<flutter::MethodChannel<Value>> CreateUpdateChannel(flutter::BinaryMessenger* messenger, HWND window) {
  auto channel = std::make_unique<flutter::MethodChannel<Value>>(messenger, "cn.privatetodo/updates", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([window](const flutter::MethodCall<Value>& call, std::unique_ptr<flutter::MethodResult<Value>> result) {
    try {
      const auto root = UpdatesRoot();
      if (call.method_name() == "identity") {
        result->Success(Value(Map{{Value("platform"), Value("windows")}, {Value("versionName"), Value(Version())}, {Value("versionCode"), Value(static_cast<int32_t>(FLUTTER_VERSION_BUILD))}, {Value("directory"), Value(root.u8string())}, {Value("enabled"), Value(true)}})); return;
      }
      if (call.method_name() == "freeSpace") {
        ULARGE_INTEGER free{};
        if (!GetDiskFreeSpaceExW(root.c_str(), &free, nullptr, nullptr)) throw std::runtime_error("space");
        result->Success(Value(static_cast<int64_t>(free.QuadPart))); return;
      }
      const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
      if (!args) throw std::runtime_error("identity");
      if (call.method_name() == "openPage") {
        const auto url = Text(*args, "url");
        if (!std::regex_match(url, std::regex("https://github\\.com/whytree222/nas-todo/releases/tag/v[0-9]+\\.[0-9]+\\.[0-9]+"))) throw std::runtime_error("identity");
        const std::wstring wide(url.begin(), url.end());
        if (reinterpret_cast<INT_PTR>(ShellExecuteW(window, L"open", wide.c_str(), nullptr, nullptr, SW_SHOWNORMAL)) <= 32) throw std::runtime_error("installer");
        result->Success(); return;
      }
      if (call.method_name() != "verify" && call.method_name() != "install") { result->NotImplemented(); return; }
      const auto version = Text(*args, "versionName");
      const auto code = Number(*args, "versionCode");
      const auto size = Number(*args, "size");
      const auto package = fs::u8path(Text(*args, "path"));
      if (!Within(root, package) || package.filename().u8string() != "nas-todo-" + version + ".zip" || !fs::is_regular_file(package) || size < 1 || size > 100 * 1024 * 1024 || fs::file_size(package) != static_cast<uint64_t>(size)) throw std::runtime_error("identity");
      if (Hash(package) != Text(*args, "sha256")) throw std::runtime_error("hash");
      const fs::path stage(package.wstring() + L".stage");
      VerifyStage(stage, version, static_cast<int>(code));
      if (call.method_name() == "verify") { result->Success(); return; }
      if (code <= FLUTTER_VERSION_BUILD || IsIconic(window) || !IsWindowVisible(window)) throw std::runtime_error("busy");
      const auto target = ExePath().parent_path();
      if (!NoLinks(target)) throw std::runtime_error("identity");
      const auto helper = root / (L"update-helper-" + std::to_wstring(GetCurrentProcessId()) + L".exe");
      fs::copy_file(target / L"nas_todo_updater.exe", helper, fs::copy_options::overwrite_existing);
      const auto inventory = Hash(stage / L"update-files.txt");
      const auto nonce = std::to_wstring(GetTickCount64());
      const auto eventName = L"Local\\CNTodoUpdate-" + std::to_wstring(GetCurrentProcessId()) + L"-" + nonce;
      HANDLE ready = CreateEventW(nullptr, TRUE, FALSE, (eventName + L"-ready").c_str());
      HANDLE proceed = CreateEventW(nullptr, TRUE, FALSE, (eventName + L"-proceed").c_str());
      if (!ready || !proceed) { if (ready) CloseHandle(ready); if (proceed) CloseHandle(proceed); throw std::runtime_error("installer"); }
      const std::wstring argsText = L"--apply " + Quote(stage.wstring()) + L" " + Quote(target.wstring()) + L" " + std::to_wstring(GetCurrentProcessId()) + L" " + Quote(std::wstring(version.begin(), version.end())) + L" " + std::to_wstring(code) + L" " + std::wstring(inventory.begin(), inventory.end()) + L" " + nonce;
      const bool launched = Launch(helper, argsText, root);
      const bool acknowledged = launched && WaitForSingleObject(ready, 10000) == WAIT_OBJECT_0;
      if (acknowledged) SetEvent(proceed);
      CloseHandle(ready); CloseHandle(proceed);
      if (!acknowledged) throw std::runtime_error("installer");
      result->Success(Value("started"));
      PostMessageW(window, WM_APP + 48, 0, 0);
    } catch (const std::exception& e) { const std::string code = e.what(); result->Error(code == "hash" || code == "identity" || code == "space" || code == "busy" ? code : "installer", "Update rejected"); }
    catch (...) { result->Error("identity", "Update rejected"); }
  });
  return channel;
}
