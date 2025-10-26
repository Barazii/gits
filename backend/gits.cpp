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
                std::string key = line.substr(0, eq_pos);
                std::string value = line.substr(eq_pos + 1);
                // Trim whitespace
                key.erase(key.begin(), std::find_if(key.begin(), key.end(), [](unsigned char ch) { return !std::isspace(ch); }));
                key.erase(std::find_if(key.rbegin(), key.rend(), [](unsigned char ch) { return !std::isspace(ch); }).base(), key.end());
                value.erase(value.begin(), std::find_if(value.begin(), value.end(), [](unsigned char ch) { return !std::isspace(ch); }));
                value.erase(std::find_if(value.rbegin(), value.rend(), [](unsigned char ch) { return !std::isspace(ch); }).base(), value.end());
                config[key] = value;
            }
        }
    }
    return config;
}

// Struct for parsed arguments
struct Args {
    std::string schedule_time;
    std::string commit_message;
    std::vector<std::string> files;
    bool status = false;
    std::string delete_job_id;
};

// Function to parse command line arguments
Args parse_args(int argc, char* argv[]) {
    Args args;
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "-m" || arg == "--message") {
            if (i + 1 >= argc || (argv[i+1][0] == '-' && !std::isdigit(argv[i+1][1]))) {
                std::cerr << "Error: -m|--message requires a commit message" << std::endl;
                std::exit(2);
            }
            args.commit_message = argv[++i];
        } else if (arg == "-f" || arg == "--file") {
            if (i + 1 >= argc) {
                std::cerr << "Error: -f|--file requires a file path" << std::endl;
                std::exit(2);
            }
            std::string files_str = argv[++i];
            // Support comma-separated
            std::stringstream ss(files_str);
            std::string file;
            while (std::getline(ss, file, ',')) {
                if (!file.empty()) {
                    args.files.push_back(file);
                }
            }
        } else if (arg == "-h" || arg == "--help") {
            std::cout << "Usage: gits <schedule-time> [-m|--message \"commit message\"] [-f|--file <path>]..." << std::endl;
            std::cout << "       gits --status" << std::endl;
            std::cout << "       gits --delete <job_id>" << std::endl;
            std::cout << "Examples:" << std::endl;
            std::cout << "  gits '2025-07-17T15:00:00Z' -m 'Fix: docs'" << std::endl;
            std::cout << "  gits '2025-07-17T15:00:00Z' -f app.py -f README.md" << std::endl;
            std::cout << "  gits '2025-07-17T15:00:00Z' -f app.py,README.md" << std::endl;
            std::cout << "  gits --status" << std::endl;
            std::cout << "  gits --delete job-123" << std::endl;
            std::exit(0);
        } else if (arg == "--status") {
            args.status = true;
        } else if (arg == "--delete") {
            if (i + 1 >= argc) {
                std::cerr << "Error: --delete requires a job_id" << std::endl;
                std::exit(2);
            }
            args.delete_job_id = argv[++i];
        } else {
            if (args.schedule_time.empty()) {
                args.schedule_time = arg;
            } else {
                std::cerr << "Error: unexpected argument: " << arg << std::endl;
                std::cerr << "Usage: gits <schedule-time> [-m|--message \"commit message\"] [-f|--file <path>]..." << std::endl;
                std::exit(2);
            }
        }
    }
    return args;
}

// Function to execute shell command and return output
std::string exec_command(const std::string& cmd) {
    std::array<char, 128> buffer;
    std::string result;
    std::unique_ptr<FILE, decltype(&pclose)> pipe(popen(cmd.c_str(), "r"), pclose);
    if (!pipe) {
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
    auto user_id_it = config.find("USER_ID");
    if (user_id_it == config.end() || user_id_it->second.empty()) {
        std::cerr << "Error: USER_ID not set in ~/.gits/config" << std::endl;
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
    auto user_id_it = config.find("USER_ID");
    if (user_id_it == config.end() || user_id_it->second.empty()) {
        std::cerr << "Error: USER_ID not set in ~/.gits/config" << std::endl;
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
bool validate_schedule_time(const std::string& time_str) {
    std::regex iso_regex(R"(^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$)");
    if (!std::regex_match(time_str, iso_regex)) {
        std::cerr << "Error: Time must be in ISO 8601 UTC format: YYYY-MM-DDTHH:MM:SSZ (e.g. 2025-07-17T15:00:00Z)" << std::endl;
        return false;
    }
    std::tm tm = {};
    std::istringstream ss(time_str);
    ss >> std::get_time(&tm, "%Y-%m-%dT%H:%M:%SZ");
    if (ss.fail()) {
        std::cerr << "Error: Invalid time format." << std::endl;
        return false;
    }
    tm.tm_isdst = 0;  // Ensure no DST adjustment
    auto tp = std::chrono::system_clock::from_time_t(timegm(&tm));
    auto now = std::chrono::system_clock::now();
    if (tp <= now) {
        std::cerr << "Error: Schedule time must be in the future." << std::endl;
        return false;
    }
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
        if (output.substr(0, 8) != "https://") {
            std::cerr << "Error: Repository URL must be HTTPS." << std::endl;
            std::cerr << "Update your remote URL to HTTPS format using: git remote set-url origin <https-url>" << std::endl;
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
            path.erase(path.begin(), std::find_if(path.begin(), path.end(), [](unsigned char ch) { return !std::isspace(ch); }));
            path.erase(std::find_if(path.rbegin(), path.rend(), [](unsigned char ch) { return !std::isspace(ch); }).base(), path.end());
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

// Function to send schedule request
void send_schedule_request(const std::string& schedule_time, const std::string& repo_url, const std::string& zip_filename, const std::string& zip_b64, const std::string& commit_message, const std::map<std::string, std::string>& config) {
    auto api_url_it = config.find("API_GATEWAY_URL");
    auto github_token_it = config.find("AWS_GITHUB_TOKEN_SECRET");
    auto user_id_it = config.find("USER_ID");
    auto github_user_it = config.find("GITHUB_USER");
    auto github_email_it = config.find("GITHUB_EMAIL");

    if (api_url_it == config.end() || api_url_it->second.empty()) {
        std::cerr << "Error: API_GATEWAY_URL not set in ~/.gits/config" << std::endl;
        std::exit(1);
    }
    if (github_token_it == config.end() || github_token_it->second.empty()) {
        std::cerr << "Error: AWS_GITHUB_TOKEN_SECRET not set in ~/.gits/config" << std::endl;
        std::exit(1);
    }
    if (user_id_it == config.end() || user_id_it->second.empty()) {
        std::cerr << "Error: USER_ID not set in ~/.gits/config" << std::endl;
        std::exit(1);
    }

    std::string url = api_url_it->second + "/schedule";
    json payload = {
        {"schedule_time", schedule_time},
        {"repo_url", repo_url},
        {"zip_filename", fs::path(zip_filename).filename().string()},
        {"zip_base64", zip_b64},
        {"github_token_secret", github_token_it->second},
        {"github_user", github_user_it != config.end() ? github_user_it->second : ""},
        {"github_email", github_email_it != config.end() ? github_email_it->second : ""},
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
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
    CURLcode res = curl_easy_perform(curl);
    long http_code = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
    curl_easy_cleanup(curl);
    curl_slist_free_all(headers);
    if (res != CURLE_OK || http_code != 200) {
        std::cerr << "Error: Remote scheduling failed (status " << http_code << "). Response: " << response << std::endl;
        std::exit(1);
    }
    std::cout << "Successfully scheduled" << std::endl;
}

int main(int argc, char* argv[]) {
    curl_global_init(CURL_GLOBAL_DEFAULT);
    auto config = load_config();
    auto args = parse_args(argc, argv);

    if (args.status) {
        handle_status(config);
        return 0;
    }

    if (!args.delete_job_id.empty()) {
        handle_delete(args.delete_job_id, config);
        return 0;
    }

    if (args.schedule_time.empty()) {
        std::cerr << "Error: Schedule time required." << std::endl;
        std::cerr << "Usage: gits <schedule-time> [-m|--message \"commit message\"] [-f|--file <path>]..." << std::endl;
        std::cerr << "Example:" << std::endl;
        std::cerr << "  gits '2025-07-17T15:00:00Z' -m 'Fix: docs'" << std::endl;
        std::cerr << "  gits '2025-07-17T15:00:00Z' -f app.py -f README.md" << std::endl;
        std::cerr << "  gits '2025-07-17T15:00:00Z' -f app.py,README.md" << std::endl;
        return 1;
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