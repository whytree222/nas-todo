#include "update_files.h"
#include <shellapi.h>
#include <chrono>
#include <fstream>
#include <iostream>

using namespace app_update;

static void Write(const fs::path& path, const std::string& value) {
  fs::create_directories(path.parent_path()); std::ofstream out(path, std::ios::binary); out << value;
  if (!out) throw std::runtime_error("storage");
}
static int SelfTest() {
  wchar_t temporary[MAX_PATH];
  if (!GetTempPathW(MAX_PATH, temporary)) return 10;
  const auto root = fs::path(temporary) / (L"nas-todo-updater-test-" + std::to_wstring(GetCurrentProcessId()));
  if (fs::exists(root)) return 11;
  const auto stage = root / L"stage", target = root / L"target", backup = root / L"backup";
  try {
    for (const auto& invalid : {"../escape.exe", "C:/evil.exe", "data/../bad", "data/NUL.txt", "data/test:stream", "other/test.dll", "data/a\\b"}) if (SafeRelative(invalid)) return 12;
    Write(stage / L"one.dll", "abc"); Write(stage / L"two.dll", "new two");
    if (Hash(stage / L"one.dll") != "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") return 13;
    Write(target / L"one.dll", "old one"); Write(target / L"two.dll", "old two"); Write(target / L"tasks.json", "keep user file");
    std::vector<FileEntry> files{{Hash(stage / L"one.dll"), L"one.dll"}, {Hash(stage / L"two.dll"), L"two.dll"}};
    HANDLE lock = CreateFileW((target / L"two.dll").c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    if (lock == INVALID_HANDLE_VALUE) return 14;
    const auto oldHash = Hash(target / L"one.dll");
    const bool accepted = ApplyFiles(stage, target, backup, files);
    CloseHandle(lock);
    if (accepted || Hash(target / L"one.dll") != oldHash) return 15;
    if (!ApplyFiles(stage, target, backup, files)) return 16;
    if (Hash(target / L"one.dll") != files[0].hash || !fs::exists(target / L"tasks.json")) return 17;
    // This path is created above from the OS temp root and a fixed test prefix.
    fs::remove_all(root);
    return 0;
  } catch (...) { return 18; }
}
int APIENTRY wWinMain(HINSTANCE, HINSTANCE, wchar_t*, int) {
  int argc = 0; LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (!argv) return 1;
  std::vector<std::wstring> args;
  for (int i = 1; i < argc; ++i) args.emplace_back(argv[i]);
  LocalFree(argv);
  if (args.size() == 1 && args[0] == L"--self-test") return SelfTest();
  if (args.size() != 8 || args[0] != L"--apply") return 2;
  fs::path restartTarget;
  try {
    const fs::path stage(args[1]), target(args[2]);
    const auto pid = static_cast<DWORD>(std::stoul(args[3]));
    const std::string version(args[4].begin(), args[4].end());
    const int code = std::stoi(args[5]);
    const std::string inventoryHash(args[6].begin(), args[6].end());
    if (pid == GetCurrentProcessId() || !Within(UpdatesRoot(), stage) || !NoLinks(target) || Hash(stage / L"update-files.txt") != inventoryHash) return 3;
    VerifyStage(stage, version, code);
    HANDLE parent = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!parent) return 4;
    std::vector<wchar_t> parentPath(32768); DWORD count = static_cast<DWORD>(parentPath.size());
    const bool identity = QueryFullProcessImageNameW(parent, 0, parentPath.data(), &count) &&
        fs::equivalent(fs::path(std::wstring(parentPath.data(), count)), target / L"nas_todo.exe");
    if (!identity) { CloseHandle(parent); return 5; }
    const auto eventName = L"Local\\CNTodoUpdate-" + std::to_wstring(pid) + L"-" + args[7];
    HANDLE ready = OpenEventW(EVENT_MODIFY_STATE, FALSE, (eventName + L"-ready").c_str());
    HANDLE proceed = OpenEventW(SYNCHRONIZE, FALSE, (eventName + L"-proceed").c_str());
    if (!ready || !proceed) { if (ready) CloseHandle(ready); if (proceed) CloseHandle(proceed); CloseHandle(parent); return 20; }
    SetEvent(ready); CloseHandle(ready);
    const DWORD confirmed = WaitForSingleObject(proceed, 10000); CloseHandle(proceed);
    if (confirmed != WAIT_OBJECT_0) { CloseHandle(parent); return 21; }
    const DWORD waited = WaitForSingleObject(parent, 30000); CloseHandle(parent);
    if (waited != WAIT_OBJECT_0) return 6;
    restartTarget = target;
    // Bind staged file bytes again after waiting for the main process to exit.
    if (Hash(stage / L"update-files.txt") != inventoryHash) throw std::runtime_error("hash");
    const auto verified = VerifyStage(stage, version, code);
    const auto stamp = std::chrono::system_clock::now().time_since_epoch().count();
    const auto backup = UpdatesRoot() / (L"backup-" + std::to_wstring(stamp));
    fs::create_directories(backup);
    const bool applied = ApplyFiles(stage, target, backup, verified);
    Write(UpdatesRoot() / L"update-result.txt", applied ? "success " + version : "failed: previous program restored; backup retained");
    Launch(target / L"nas_todo.exe", L"", target);
    return applied ? 0 : 8;
  } catch (...) {
    if (!restartTarget.empty()) {
      try { Write(UpdatesRoot() / L"update-result.txt", "failed: update preparation did not finish; program files retained"); } catch (...) {}
      Launch(restartTarget / L"nas_todo.exe", L"", restartTarget);
    }
    return 9;
  }
}
