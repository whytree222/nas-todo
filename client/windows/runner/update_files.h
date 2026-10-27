#pragma once
#include <windows.h>
#include <filesystem>
#include <string>
#include <vector>

namespace app_update {
namespace fs = std::filesystem;
struct FileEntry { std::string hash; fs::path relative; };
fs::path ExePath();
fs::path UpdatesRoot();
bool NoLinks(const fs::path& path);
bool Within(const fs::path& root, const fs::path& path);
bool SafeRelative(const std::string& name);
std::string Hash(const fs::path& path);
bool VersionMatches(const fs::path& executable, const std::string& version, int code);
std::vector<FileEntry> VerifyStage(const fs::path& stage, const std::string& version, int code);
bool ApplyFiles(const fs::path& stage, const fs::path& target, const fs::path& backup, const std::vector<FileEntry>& files);
std::wstring Quote(const std::wstring& value);
bool Launch(const fs::path& executable, const std::wstring& arguments, const fs::path& working);
}
