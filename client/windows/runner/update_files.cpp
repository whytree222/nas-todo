#include "update_files.h"
#include <bcrypt.h>
#include <shlobj.h>
#include <algorithm>
#include <array>
#include <cwctype>
#include <fstream>
#include <iomanip>
#include <regex>
#include <set>
#include <sstream>
#include <stdexcept>

namespace app_update {
fs::path ExePath() {
  std::vector<wchar_t> path(32768);
  DWORD count = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (!count || count >= path.size()) throw std::runtime_error("path");
  return fs::path(std::wstring(path.data(), count));
}
fs::path UpdatesRoot() {
  PWSTR path = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &path))) throw std::runtime_error("storage");
  fs::path root = fs::path(path) / L"NAS Todo" / L"updates";
  CoTaskMemFree(path); fs::create_directories(root); return root;
}
bool NoLinks(const fs::path& path) {
  fs::path current;
  for (const auto& part : fs::absolute(path)) {
    current /= part;
    const DWORD attributes = GetFileAttributesW(current.c_str());
    if (attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_REPARSE_POINT)) return false;
  }
  return true;
}
bool Within(const fs::path& root, const fs::path& path) {
  auto r = fs::absolute(root).lexically_normal().wstring();
  auto p = fs::absolute(path).lexically_normal().wstring();
  std::transform(r.begin(), r.end(), r.begin(), ::towlower);
  std::transform(p.begin(), p.end(), p.begin(), ::towlower);
  return p.size() > r.size() && p.compare(0, r.size(), r) == 0 && p[r.size()] == L'\\' && NoLinks(path);
}
bool SafeRelative(const std::string& name) {
  if (name.empty() || name.size() > 220 || name.front() == '/' || name.find_first_of("\\:*?\"<>|\r\n") != std::string::npos || name.find('\0') != std::string::npos) return false;
  std::istringstream input(name); std::string part;
  while (std::getline(input, part, '/')) {
    if (part.empty() || part == "." || part == ".." || part.back() == '.' || part.back() == ' ' ||
        std::regex_search(part, std::regex("^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(\\.|$)", std::regex::icase))) return false;
  }
  if (name.find('/') != std::string::npos) return name.rfind("data/", 0) == 0;
  return std::regex_match(name, std::regex("[A-Za-z0-9_.-]+\\.(exe|dll|cmd)", std::regex::icase));
}
std::string Hash(const fs::path& path) {
  std::ifstream input(path, std::ios::binary);
  if (!input) throw std::runtime_error("hash");
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  BCRYPT_HASH_HANDLE hash = nullptr;
  if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0) throw std::runtime_error("hash");
  DWORD size = 0, copied = 0;
  if (BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH, reinterpret_cast<PUCHAR>(&size), sizeof(size), &copied, 0) < 0) {
    BCryptCloseAlgorithmProvider(algorithm, 0); throw std::runtime_error("hash");
  }
  std::vector<UCHAR> object(size);
  if (BCryptCreateHash(algorithm, &hash, object.data(), size, nullptr, 0, 0) < 0) { BCryptCloseAlgorithmProvider(algorithm, 0); throw std::runtime_error("hash"); }
  std::array<char, 65536> buffer;
  bool valid = true;
  while (input) {
    input.read(buffer.data(), buffer.size());
    const auto count = input.gcount();
    if (count > 0 && BCryptHashData(hash, reinterpret_cast<PUCHAR>(buffer.data()), static_cast<ULONG>(count), 0) < 0) { valid = false; break; }
  }
  std::array<UCHAR, 32> digest;
  valid = valid && !input.bad() && BCryptFinishHash(hash, digest.data(), static_cast<ULONG>(digest.size()), 0) >= 0;
  BCryptDestroyHash(hash); BCryptCloseAlgorithmProvider(algorithm, 0);
  if (!valid) throw std::runtime_error("hash");
  std::ostringstream result; result << std::hex << std::setfill('0');
  for (const auto byte : digest) result << std::setw(2) << static_cast<unsigned>(byte);
  return result.str();
}
bool VersionMatches(const fs::path& executable, const std::string& version, int code) {
  DWORD ignored = 0; const DWORD size = GetFileVersionInfoSizeW(executable.c_str(), &ignored);
  if (!size) return false;
  std::vector<BYTE> data(size);
  if (!GetFileVersionInfoW(executable.c_str(), 0, size, data.data())) return false;
  VS_FIXEDFILEINFO* fixed = nullptr; UINT length = 0;
  if (!VerQueryValueW(data.data(), L"\\", reinterpret_cast<void**>(&fixed), &length) || length < sizeof(VS_FIXEDFILEINFO) || fixed->dwSignature != 0xfeef04bd) return false;
  const std::string actual = std::to_string(HIWORD(fixed->dwFileVersionMS)) + "." + std::to_string(LOWORD(fixed->dwFileVersionMS)) + "." + std::to_string(HIWORD(fixed->dwFileVersionLS));
  if (actual != version || LOWORD(fixed->dwFileVersionLS) != code) return false;
  wchar_t* product = nullptr;
  return VerQueryValueW(data.data(), L"\\StringFileInfo\\040904e4\\ProductName", reinterpret_cast<void**>(&product), &length) && product && std::wstring(product) == L"私有待办";
}
std::vector<FileEntry> VerifyStage(const fs::path& stage, const std::string& version, int code) {
  if (!Within(UpdatesRoot(), stage)) throw std::runtime_error("identity");
  std::ifstream input(stage / L"update-files.txt");
  std::string header, name, number;
  std::getline(input, header); std::getline(input, name); std::getline(input, number);
  if (header != "NAS_TODO_UPDATE_V1" || name != version || number != std::to_string(code)) throw std::runtime_error("identity");
  std::set<std::string> seen; std::vector<FileEntry> files; std::string line;
  while (std::getline(input, line)) {
    if (line.size() < 66 || line[64] != ' ' || !std::regex_match(line.substr(0, 64), std::regex("[0-9a-f]{64}"))) throw std::runtime_error("hash");
    auto relative = line.substr(65), lower = relative;
    std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);
    if (!SafeRelative(relative) || !seen.insert(lower).second || files.size() >= 4096) throw std::runtime_error("identity");
    const auto path = stage / fs::u8path(relative);
    if (!Within(stage, path) || !fs::is_regular_file(path) || Hash(path) != line.substr(0, 64)) throw std::runtime_error("hash");
    files.push_back({line.substr(0, 64), fs::u8path(relative)});
  }
  for (const auto& required : {"nas_todo.exe", "nas_todo_updater.exe", "flutter_windows.dll", "data/icudtl.dat"}) if (!seen.count(required)) throw std::runtime_error("identity");
  if (!VersionMatches(stage / L"nas_todo.exe", version, code)) throw std::runtime_error("identity");
  return files;
}
bool ApplyFiles(const fs::path& stage, const fs::path& target, const fs::path& backup, const std::vector<FileEntry>& files) {
  struct Changed { fs::path relative; bool existed; };
  std::vector<Changed> changed;
  try {
    for (const auto& entry : files) {
      const auto destination = target / entry.relative, previous = backup / entry.relative;
      if (!Within(target, destination) || !Within(stage, stage / entry.relative) || !Within(backup, previous) || Hash(stage / entry.relative) != entry.hash) throw std::runtime_error("identity");
      const bool existed = fs::exists(destination);
      if (existed) { fs::create_directories(previous.parent_path()); fs::copy_file(destination, previous, fs::copy_options::overwrite_existing); }
      fs::create_directories(destination.parent_path());
      changed.push_back({entry.relative, existed});
      fs::copy_file(stage / entry.relative, destination, fs::copy_options::overwrite_existing);
      if (Hash(destination) != entry.hash) throw std::runtime_error("hash");
    }
    return true;
  } catch (...) {
    for (auto it = changed.rbegin(); it != changed.rend(); ++it) {
      try {
        if (it->existed) fs::copy_file(backup / it->relative, target / it->relative, fs::copy_options::overwrite_existing);
        else fs::remove(target / it->relative);
      } catch (...) { /* Keep the backup for manual recovery if a file stays locked. */ }
    }
    return false;
  }
}
std::wstring Quote(const std::wstring& value) {
  std::wstring result = L"\""; size_t slashes = 0;
  for (wchar_t c : value) {
    if (c == L'\\') { ++slashes; continue; }
    if (c == L'\"') result.append(slashes * 2 + 1, L'\\'); else result.append(slashes, L'\\');
    slashes = 0; result += c;
  }
  result.append(slashes * 2, L'\\'); return result + L"\"";
}
bool Launch(const fs::path& executable, const std::wstring& arguments, const fs::path& working) {
  std::wstring command = Quote(executable.wstring()) + L" " + arguments;
  STARTUPINFOW startup{}; startup.cb = static_cast<DWORD>(sizeof(startup)); PROCESS_INFORMATION process{};
  const bool launched = CreateProcessW(executable.c_str(), command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, working.c_str(), &startup, &process) != FALSE;
  if (launched) { CloseHandle(process.hThread); CloseHandle(process.hProcess); }
  return launched;
}
}
