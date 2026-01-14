#include <iostream>
#include <string>
#include <vector>
#include <map>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <regex>
#include <chrono>
#include <iomanip>
#include <cstdlib>
#include <cstdio>
#include <ctime>
#include <memory>
#include <array>
#include <algorithm>
#include <set>

#include <curl/curl.h>
#include <nlohmann/json.hpp>
#include <openssl/bio.h>
#include <openssl/evp.h>
#include <openssl/buffer.h>
#include <zip.h>

namespace fs = std::filesystem;

using json = nlohmann::json;

// Function to trim whitespace from string
std::string trim(const std::string& str) {
    /*
    // another implementation
    path.erase(path.begin(), std::find_if(path.begin(), path.end(), [](unsigned char ch) { return !std::isspace(ch); }));
    path.erase(std::find_if(path.rbegin(), path.rend(), [](unsigned char ch) { return !std::isspace(ch); }).base(), path.end());
    */
    auto start = std::find_if(str.begin(), str.end(), [](unsigned char ch) { return !std::isspace(ch); });
    auto end = std::find_if(str.rbegin(), str.rend(), [](unsigned char ch) { return !std::isspace(ch); }).base();
    return (start < end) ? std::string(start, end) : std::string();
}

// Function to load configuration from ~/.gits/config
std::map<std::string, std::string> load_config() {
    std::map<std::string, std::string> config;
    fs::path config_path = fs::path(std::getenv("HOME")) / ".gits" / "config";
    if (fs::exists(config_path)) {
        std::ifstream config_file(config_path);
        std::string line;
        while (std::getline(config_file, line)) {
            // Simple key=value parsing, ignore comments or empty lines
            if (line.empty() || line[0] == '#') continue;
            size_t eq_pos = line.find('=');
            if (eq_pos != std::string::npos) {
                std::string key = trim(line.substr(0, eq_pos));
                std::string value_part = line.substr(eq_pos + 1);
                std::string value;
                if (!value_part.empty() && value_part[0] == '"') {
                    value = value_part.substr(1);
                    bool in_quote = true;
                    while (in_quote && std::getline(config_file, line)) {
                        size_t quote_pos = line.find('"');
                        if (quote_pos != std::string::npos) {
                            value += line.substr(0, quote_pos);
                            in_quote = false;
                        } else {
                            value += line + "\n";
                        }
                    }
                    if (in_quote) {
                        std::cerr << "Error: Unclosed quote in config for key: " << key << std::endl;
                        continue;
                    }
                } else {
                    value = trim(value_part);
                }
                config[key] = value;
            }
        }
    }
    return config;
}

// Struct for parsed arguments
struct Args {
    std::string command;
    std::string schedule_time;
    std::string commit_message;
    std::vector<std::string> files;
    std::string delete_job_id;
    bool show_version = false;
};

// Function to parse command line arguments
Args parse_args(int argc, char* argv[]) {
    Args args;
    if (argc < 2) {
        std::cerr << "Usage: gits <command> [options]" << std::endl;
        std::cerr << "Commands:" << std::endl;
        std::cerr << "  schedule --schedule_time <time> [--message <msg>] [--file <path>]..." << std::endl;
        std::cerr << "  status" << std::endl;
        std::cerr << "  delete --job_id <id>" << std::endl;
        std::cerr << "  version" << std::endl;
        std::exit(2);
    }
    std::string command = argv[1];
    args.command = command;
    if (command == "--version" or command == "version") {
        args.show_version = true;
        return args;
    }
    if (command == "schedule") {
        bool has_schedule_time = false;
        for (int i = 2; i < argc; ++i) {
            std::string arg = argv[i];
            if (arg == "--schedule_time") {
                if (i + 1 >= argc) {
                    std::cerr << "Error: --schedule_time requires a time value" << std::endl;
                    std::exit(2);
                }
                args.schedule_time = argv[++i];
                has_schedule_time = true;
            } else if (arg == "--message") {
                if (i + 1 >= argc) {
                    std::cerr << "Error: --message requires a commit message" << std::endl;
                    std::exit(2);
                }
                args.commit_message = argv[++i];
            } else if (arg == "--file") {
                if (i + 1 >= argc) {
                    std::cerr << "Error: --file requires a file path" << std::endl;
                    std::exit(2);
                }
                std::string files_str = argv[++i];
                std::stringstream ss(files_str);
                std::string file;
                while (std::getline(ss, file, ',')) {
                    if (!file.empty()) {
                        args.files.push_back(file);
                    }
                }
            } else {
                std::cerr << "Error: unknown option for schedule: " << arg << std::endl;
                std::exit(2);
            }
        }
        if (!has_schedule_time) {
            std::cerr << "Error: schedule requires --schedule_time <time>" << std::endl;
            std::exit(2);
        }
    } else if (command == "status") {
        if (argc > 2) {
            std::cerr << "Error: status takes no arguments" << std::endl;
            std::exit(2);
        }
    } else if (command == "delete") {
        if (argc < 4 || std::string(argv[2]) != "--job_id") {
            std::cerr << "Error: delete requires --job_id <id>" << std::endl;
            std::exit(2);
        }
        args.delete_job_id = argv[3];
        if (argc > 4) {
            std::cerr << "Error: delete takes only --job_id <id>" << std::endl;
            std::exit(2);
        }
    } else if (command == "-h" || command == "--help" || command == "help") {
        std::cout << "Usage: gits <command> [options]" << std::endl;
        std::cout << "Commands:" << std::endl;
        std::cout << "  schedule --schedule_time <time> [--message <msg>] [--file <path>]..." << std::endl;
        std::cout << "  status" << std::endl;
        std::cout << "  delete --job_id <id>" << std::endl;
        std::cout << "  version" << std::endl;
        std::cout << "Examples:" << std::endl;
        std::cout << "  gits schedule --schedule_time 2025-07-17T15:00 --message 'Fix: docs'" << std::endl;
        std::cout << "  gits schedule --schedule_time 2025-07-17T15:00 --file app.py --file README.md" << std::endl;
        std::cout << "  gits schedule --schedule_time 2025-07-17T15:00 --file app.py,README.md" << std::endl;
        std::cout << "  gits status" << std::endl;
        std::cout << "  gits delete --job_id job-123" << std::endl;
        std::exit(0);
    } else {
        std::cerr << "Error: unknown command: " << command << std::endl;
        std::cerr << "See 'gits --help'" << std::endl;
        std::exit(2);
    }
    return args;
}

// Function to execute shell command and return output
std::string exec_command(const std::string& cmd) {
    std::array<char, 128> buffer;
    std::string result;
    class Pipe {
        public:
            Pipe(FILE* f) : file(f) {}
            ~Pipe() { if (file) pclose(file); }
            FILE* get() { return file; }
        private:
            FILE* file;
    };
    // std::unique_ptr<FILE, int(*)(FILE*)> pipe(popen(cmd.c_str(), "r"), pclose);
    Pipe pipe(popen(cmd.c_str(), "r"));
    if (!pipe.get()) {
        throw std::runtime_error("popen() failed!");
    }
    while (fgets(buffer.data(), buffer.size(), pipe.get()) != nullptr) {
        result += buffer.data();
    }
    return result;
}

// Function to check if command succeeded
bool exec_command_success(const std::string& cmd) {
    int ret = std::system(cmd.c_str());
    return ret == 0;
}

// Callback for libcurl to write response
size_t write_callback(void* contents, size_t size, size_t nmemb, std::string* response) {
    size_t total_size = size * nmemb;
    response->append((char*)contents, total_size);
    return total_size;
}

// Function to handle status command
void handle_status(const std::map<std::string, std::string>& config) {
    if (!exec_command_success("git rev-parse --git-dir > /dev/null 2>&1")) {
        std::cerr << "Error: Not a git repository" << std::endl;
        std::exit(1);
    }
    auto api_url_it = config.find("API_GATEWAY_URL");
    if (api_url_it == config.end() || api_url_it->second.empty()) {
        std::cerr << "Error: API_GATEWAY_URL not set in ~/.gits/config" << std::endl;
        std::exit(1);
    }
    auto user_id_it = config.find("GITHUB_EMAIL");
    if (user_id_it == config.end() || user_id_it->second.empty()) {
        std::cerr << "Error: GITHUB_EMAIL not set in ~/.gits/config" << std::endl;
        std::exit(1);
    }
    std::string url = api_url_it->second + "/status?user_id=" + user_id_it->second;

    CURL* curl = curl_easy_init();
    if (!curl) {
        std::cerr << "Error: Failed to initialize curl" << std::endl;
        std::exit(1);
    }
    std::string response;
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
    CURLcode res = curl_easy_perform(curl);
    long http_code = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
    curl_easy_cleanup(curl);
    if (res != CURLE_OK || http_code != 200) {
        std::cerr << response << std::endl;
        std::exit(1);
    }
    try {
        json j = json::parse(response);
        std::string schedule_time = j.value("schedule_time", "");
        std::string status = j.value("status", "");
        std::string job_id = j.value("job_id", "");
        std::cout << "Job ID: " << job_id << std::endl;
        std::cout << "Schedule Time: " << schedule_time << std::endl;
        std::cout << "Status: " << status << std::endl;
    } catch (const json::parse_error& e) {
        std::cerr << "Error parsing JSON response" << std::endl;
        std::exit(1);
    }
}

// Function to handle delete command
void handle_delete(const std::string& job_id, const std::map<std::string, std::string>& config) {
    if (!exec_command_success("git rev-parse --git-dir > /dev/null 2>&1")) {
        std::cerr << "Error: Not a git repository" << std::endl;
        std::exit(1);
    }
    auto api_url_it = config.find("API_GATEWAY_URL");
    if (api_url_it == config.end() || api_url_it->second.empty()) {
        std::cerr << "Error: API_GATEWAY_URL not set in ~/.gits/config" << std::endl;
        std::exit(1);
    }
    auto user_id_it = config.find("GITHUB_EMAIL");
    if (user_id_it == config.end() || user_id_it->second.empty()) {
        std::cerr << "Error: GITHUB_EMAIL not set in ~/.gits/config" << std::endl;
        std::exit(1);
    }
    std::string url = api_url_it->second + "/delete";
    json payload = {
        {"job_id", job_id},
        {"user_id", user_id_it->second}
    };
    std::string payload_str = payload.dump();

    CURL* curl = curl_easy_init();
    if (!curl) {
        std::cerr << "Error: Failed to initialize curl" << std::endl;
        std::exit(1);
    }
    std::string response;
    struct curl_slist* headers = nullptr;
    headers = curl_slist_append(headers, "Content-Type: application/json");
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_POST, 1L);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, payload_str.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
    CURLcode res = curl_easy_perform(curl);
    long http_code = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
    curl_easy_cleanup(curl);
    curl_slist_free_all(headers);
    if (res != CURLE_OK || http_code != 200) {
        std::cerr << "Error: Delete failed (status " << http_code << "). Response: " << response << std::endl;
        std::exit(1);
    }
    std::cout << "Job deleted successfully" << std::endl;
}

// Function to validate schedule time
bool validate_schedule_time(std::string& time_str) {
    std::regex time_regex(R"(^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$)");
    if (!std::regex_match(time_str, time_regex)) {
        std::cerr << "Error: Time must be in format: YYYY-MM-DDTHH:MM (local time, e.g. 2025-07-17T15:00)" << std::endl;
        return false;
    }
    std::tm tm = {};
    std::istringstream ss(time_str);
    ss >> std::get_time(&tm, "%Y-%m-%dT%H:%M");
    if (ss.fail()) {
        std::cerr << "Error: Invalid time format." << std::endl;
        return false;
    }
    tm.tm_sec = 0;
    tm.tm_isdst = -1;  // Let mktime determine DST
    time_t local_time = mktime(&tm);
    if (local_time == -1) {
        std::cerr << "Error: Invalid time." << std::endl;
        return false;
    }
    auto tp = std::chrono::system_clock::from_time_t(local_time);
    auto now = std::chrono::system_clock::now();
    if (tp <= now) {
        std::cerr << "Error: Schedule time must be in the future." << std::endl;
        return false;
    }
    // Convert to UTC ISO8601
    std::ostringstream oss;
    oss << std::put_time(std::gmtime(&local_time), "%FT%TZ");
    time_str = oss.str();
    return true;
}

// Function to get repo URL
std::string get_repo_url() {
    try {
        std::string output = exec_command("git remote get-url origin 2>/dev/null");
        if (output.empty()) {
            std::cerr << "Error: Could not retrieve repository URL. Ensure 'origin' remote is set." << std::endl;
            std::exit(1);
        }
        // Trim newline
        output.erase(output.find_last_not_of("\n\r") + 1);
        bool is_https = output.substr(0, 8) == "https://";
        bool is_ssh_git = output.substr(0, 4) == "git@";
        bool is_ssh_url = output.substr(0, 10) == "ssh://git@";
        if (!is_https && !is_ssh_git && !is_ssh_url) {
            std::cerr << "Error: Repository URL must be HTTPS or SSH format for GitHub." << std::endl;
            std::exit(1);
        }
        return output;
    } catch (...) {
        std::cerr << "Error: Could not retrieve repository URL." << std::endl;
        std::exit(1);
    }
}

// Struct for file changes
struct FileChanges {
    std::vector<std::string> files_to_zip;
    std::vector<std::string> deletes_for_manifest;
};

// Function to gather file changes
FileChanges gather_file_changes(const std::vector<std::string>& specified_files) {
    FileChanges changes;
    std::string git_status = exec_command("git status --porcelain -M");
    std::vector<std::string> deleted_paths;
    std::vector<std::pair<std::string, std::string>> renames;

    std::istringstream iss(git_status);
    std::string line;
    while (std::getline(iss, line)) {
        if (line.size() < 3) continue;
        char x = line[0], y = line[1];
        std::string path = line.substr(3);
        if (x == 'D' || y == 'D') {
            deleted_paths.push_back(path);
        }
        if (x == 'R' || y == 'R') {
            // Parse rename: old -> new
            size_t arrow_pos = path.find(" -> ");
            if (arrow_pos != std::string::npos) {
                std::string old_path = path.substr(0, arrow_pos);
                std::string new_path = path.substr(arrow_pos + 4);
                renames.emplace_back(old_path, new_path);
            }
        }
    }

    auto in_vector = [](const std::string& item, const std::vector<std::string>& vec) {
        return std::find(vec.begin(), vec.end(), item) != vec.end();
    };

    if (!specified_files.empty()) {
        for (const auto& f : specified_files) {
            if (fs::exists(f)) {
                changes.files_to_zip.push_back(f);
            } else if (in_vector(f, deleted_paths) || std::any_of(renames.begin(), renames.end(), [&](const auto& p){ return p.first == f || p.second == f; })) {
                // It's deleted or part of rename, handle in manifest
            } else {
                std::cerr << "Error: file not found: " << f << std::endl;
                std::exit(1);
            }
        }
        // Filter deletes and renames to specified
        for (const auto& d : deleted_paths) {
            if (in_vector(d, specified_files)) {
                changes.deletes_for_manifest.push_back(d);
            }
        }
        for (const auto& r : renames) {
            if (in_vector(r.first, specified_files) && in_vector(r.second, specified_files)) {
                if (fs::exists(r.second) && !in_vector(r.second, changes.files_to_zip)) {
                    changes.files_to_zip.push_back(r.second);
                }
                changes.deletes_for_manifest.push_back(r.first);
            }
        }
    } else {
        // Auto-detect
        std::istringstream iss(git_status);
        std::string line;
        while (std::getline(iss, line)) {
            if (line.size() < 3) continue;
            char x = line[0], y = line[1];
            std::string path = line.substr(3);
            // Trim whitespace from path
            path = trim(path);
            if ((x == 'A' && y == ' ') || (x == 'M' && y == ' ') || (x == ' ' && y == 'M') || (x == 'M' && y == 'M') || (x == '?' && y == '?')) {
                changes.files_to_zip.push_back(path);
            }
        }
        for (const auto& r : renames) {
            if (fs::exists(r.second) && !in_vector(r.second, changes.files_to_zip)) {
                changes.files_to_zip.push_back(r.second);
            }
        }
        changes.deletes_for_manifest = deleted_paths;
        for (const auto& r : renames) {
            changes.deletes_for_manifest.push_back(r.first);
        }
        if (changes.files_to_zip.empty() && changes.deletes_for_manifest.empty()) {
            std::cerr << "No changes found." << std::endl;
            std::exit(1);
        }
    }

    // Deduplicate
    std::set<std::string> unique_zip(changes.files_to_zip.begin(), changes.files_to_zip.end());
    changes.files_to_zip.assign(unique_zip.begin(), unique_zip.end());
    std::set<std::string> unique_del(changes.deletes_for_manifest.begin(), changes.deletes_for_manifest.end());
    changes.deletes_for_manifest.assign(unique_del.begin(), unique_del.end());

    return changes;
}

// Function to create zip file
std::string create_zip(const FileChanges& changes) {
    std::string zip_filename = "/tmp/gits-changes-" + std::to_string(std::time(nullptr)) + ".zip";
    int err = 0;
    zip_t* z = zip_open(zip_filename.c_str(), ZIP_CREATE | ZIP_TRUNCATE, &err);
    if (!z) {
        std::cerr << "Error: Failed to create zip file." << std::endl;
        std::exit(1);
    }

    // Add files to zip
    for (const auto& file : changes.files_to_zip) {
        zip_source_t* s = zip_source_file(z, file.c_str(), 0, 0);
        if (s == nullptr || zip_file_add(z, file.c_str(), s, ZIP_FL_OVERWRITE) < 0) {
            zip_source_free(s);
            std::cerr << "Error: Failed to add file to zip: " << file << std::endl;
            zip_close(z);
            std::exit(1);
        }
    }

    // Create manifest
    json manifest = {{"deleted", changes.deletes_for_manifest}};
    std::string manifest_str = manifest.dump(4);
    std::string manifest_filename = ".gits-manifest-" + std::to_string(std::time(nullptr)) + ".json";
    zip_source_t* s = zip_source_buffer(z, manifest_str.c_str(), manifest_str.size(), 0);
    if (s == nullptr || zip_file_add(z, manifest_filename.c_str(), s, ZIP_FL_OVERWRITE) < 0) {
        zip_source_free(s);
        std::cerr << "Error: Failed to add manifest to zip." << std::endl;
        zip_close(z);
        std::exit(1);
    }

    if (zip_close(z) < 0) {
        std::cerr << "Error: Failed to close zip file." << std::endl;
        std::exit(1);
    }

    return zip_filename;
}

// Function to base64 encode file
std::string base64_encode_file(const std::string& filename) {
    std::ifstream file(filename, std::ios::binary);
    if (!file) {
        std::cerr << "Error: Cannot open file for base64 encoding." << std::endl;
        std::exit(1);
    }
    std::vector<char> buffer(std::istreambuf_iterator<char>(file), {});
    file.close();

    BIO* b64 = BIO_new(BIO_f_base64());
    BIO* bio = BIO_new(BIO_s_mem());
    bio = BIO_push(b64, bio);
    BIO_write(bio, buffer.data(), buffer.size());
    BIO_flush(bio);

    BUF_MEM* buffer_ptr;
    BIO_get_mem_ptr(bio, &buffer_ptr);
    std::string encoded(buffer_ptr->data, buffer_ptr->length);
    encoded.erase(std::remove(encoded.begin(), encoded.end(), '\n'), encoded.end());
    BIO_free_all(bio);
    return encoded;
}

// Function to base64 encode a string
std::string base64_encode_string(const std::string& input) {
    BIO* b64 = BIO_new(BIO_f_base64());
    BIO* bio = BIO_new(BIO_s_mem());
    bio = BIO_push(b64, bio);
    BIO_write(bio, input.data(), input.size());
    BIO_flush(bio);
    BUF_MEM* buffer_ptr;
    BIO_get_mem_ptr(bio, &buffer_ptr);
    std::string encoded(buffer_ptr->data, buffer_ptr->length);
    encoded.erase(std::remove(encoded.begin(), encoded.end(), '\n'), encoded.end());
    BIO_free_all(bio);
    return encoded;
}

// Function to send schedule request
void send_schedule_request(const std::string& schedule_time, const std::string& repo_url, const std::string& zip_filename, const std::string& zip_b64, const std::string& commit_message, const std::map<std::string, std::string>& config) {
    auto api_url_it = config.find("API_GATEWAY_URL");
    auto user_id_it = config.find("GITHUB_EMAIL");
    auto github_username_it = config.find("GITHUB_USERNAME");
    auto github_display_name_it = config.find("GITHUB_DISPLAY_NAME");

    if (api_url_it == config.end() || api_url_it->second.empty()) {
        std::cerr << "Error: API_GATEWAY_URL not set in ~/.gits/config" << std::endl;
        std::exit(1);
    }

    if (user_id_it == config.end() || user_id_it->second.empty()) {
        std::cerr << "Error: GITHUB_EMAIL not set in ~/.gits/config" << std::endl;
        std::exit(1);
    }

    if (github_username_it == config.end() || github_username_it->second.empty()) {
        std::cerr << "Error: GITHUB_USERNAME not set in ~/.gits/config" << std::endl;
        std::exit(1);
    }

    if (github_display_name_it == config.end() || github_display_name_it->second.empty()) {
        std::cerr << "Error: GITHUB_DISPLAY_NAME not set in ~/.gits/config" << std::endl;
        std::exit(1);
    }

    std::string url = api_url_it->second + "/schedule";
    json payload = {
        {"schedule_time", schedule_time},
        {"repo_url", repo_url},
        {"zip_filename", fs::path(zip_filename).filename().string()},
        {"zip_base64", zip_b64},
        {"github_username", github_username_it != config.end() ? github_username_it->second : ""},
        {"github_display_name", github_display_name_it != config.end() ? github_display_name_it->second : ""},
        {"github_email", user_id_it->second},
        {"commit_message", commit_message},
        {"user_id", user_id_it->second}
    };
    std::string payload_str = payload.dump();

    CURL* curl = curl_easy_init();
    if (!curl) {
        std::cerr << "Error: Failed to initialize curl" << std::endl;
        std::exit(1);
    }
    std::string response;
    struct curl_slist* headers = nullptr;
    headers = curl_slist_append(headers, "Content-Type: application/json");
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_POST, 1L);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, payload_str.c_str());
    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, payload_str.size());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
    CURLcode res = curl_easy_perform(curl);
    long http_code = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
    curl_easy_cleanup(curl);
    curl_slist_free_all(headers);
    if (res != CURLE_OK) {
        std::cerr << "Error: Network request failed: " << curl_easy_strerror(res) << std::endl;
        std::exit(1);
    }
    if (http_code != 200) {
        std::cerr << "Error: Remote scheduling failed (HTTP " << http_code << "). Response: " << response << std::endl;
        std::exit(1);
    }
    std::cout << "Successfully scheduled" << std::endl;
}

int main(int argc, char* argv[]) {
    curl_global_init(CURL_GLOBAL_DEFAULT);
    auto config = load_config();
    auto args = parse_args(argc, argv);

    // Handle version display
    if (args.show_version) {
#ifdef GITS_VERSION
    std::cout << "gits " << GITS_VERSION << std::endl;
#else
    std::cout << "gits" << std::endl;
#endif
    curl_global_cleanup();
    return 0;
    }

    if (args.command == "status") {
        handle_status(config);
        return 0;
    }

    if (args.command == "delete") {
        handle_delete(args.delete_job_id, config);
        return 0;
    }

    if (!validate_schedule_time(args.schedule_time)) {
        return 1;
    }

    if (!exec_command_success("git rev-parse --is-inside-work-tree >/dev/null 2>&1")) {
        std::cerr << "Error: Must be run inside a Git repository." << std::endl;
        return 1;
    }

    std::string repo_url = get_repo_url();
    auto changes = gather_file_changes(args.files);
    std::string zip_file = create_zip(changes);
    std::string zip_b64 = base64_encode_file(zip_file);

    // Cleanup zip file
    fs::remove(zip_file);

    send_schedule_request(args.schedule_time, repo_url, zip_file, zip_b64, args.commit_message, config);

    curl_global_cleanup();
    return 0;
}