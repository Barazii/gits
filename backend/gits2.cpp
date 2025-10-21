#include <iostream>
#include <string>
#include <vector>
#include <map>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <regex>
#include <chrono>
#include <ctime>
#include <cstdlib>
#include <array>
#include <memory>
#include <algorithm>
#include <cctype>
#include <iomanip>
#include <set>

// gits: A tool to schedule Git operations for any Git repository
// Usage: gits <schedule-time> [-m|--message "commit message"] [-f|--file <path>]...
// Example: gits "2025-07-17T15:00:00Z" -m "Fix: update readme" -f backend/gits.sh -f README.md

std::string exec(const std::string& cmd) {
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

std::string trim(const std::string& s) {
    auto start = s.begin();
    while (start != s.end() && std::isspace(*start)) ++start;
    auto end = s.end();
    do --end; while (end != start && std::isspace(*end));
    return std::string(start, end + 1);
}

std::map<std::string, std::string> load_config(const std::string& config_file) {
    std::map<std::string, std::string> config;
    std::ifstream file(config_file);
    if (!file) return config;
    std::string line;
    while (std::getline(file, line)) {
        line = trim(line);
        if (line.empty() || line[0] == '#') continue;
        size_t eq = line.find('=');
        if (eq != std::string::npos) {
            std::string key = trim(line.substr(0, eq));
            std::string value = trim(line.substr(eq + 1));
            config[key] = value;
        }
    }
    return config;
}

struct Args {
    std::string schedule_time;
    std::string commit_message;
    std::vector<std::string> files;
    bool status = false;
    std::string delete_job_id;
};

Args parse_args(int argc, char* argv[]) {
    Args args;
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "-m" || arg == "--message") {
            if (i + 1 >= argc || argv[i+1][0] == '-') {
                std::cerr << "Error: -m|--message requires a commit message" << std::endl;
                exit(2);
            }
            args.commit_message = argv[++i];
        } else if (arg == "-f" || arg == "--file") {
            if (i + 1 >= argc) {
                std::cerr << "Error: -f|--file requires a file path" << std::endl;
                exit(2);
            }
            std::string files_str = argv[++i];
            std::stringstream ss(files_str);
            std::string file;
            while (std::getline(ss, file, ',')) {
                file = trim(file);
                if (!file.empty()) args.files.push_back(file);
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
            exit(0);
        } else if (arg == "--status") {
            args.status = true;
        } else if (arg == "--delete") {
            if (i + 1 >= argc) {
                std::cerr << "Error: --delete requires a job_id" << std::endl;
                exit(2);
            }
            args.delete_job_id = argv[++i];
        } else {
            if (args.schedule_time.empty()) {
                args.schedule_time = arg;
            } else {
                std::cerr << "Error: unexpected argument: " << arg << std::endl;
                std::cerr << "Usage: gits <schedule-time> [-m|--message \"commit message\"] [-f|--file <path>]..." << std::endl;
                exit(2);
            }
        }
    }
    return args;
}

std::string base64_encode(const std::vector<unsigned char>& data) {
    static const std::string base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string encoded;
    size_t i = 0;
    unsigned char char_array_3[3];
    unsigned char char_array_4[4];
    for (auto c : data) {
        char_array_3[i++] = c;
        if (i == 3) {
            char_array_4[0] = (char_array_3[0] & 0xfc) >> 2;
            char_array_4[1] = ((char_array_3[0] & 0x03) << 4) + ((char_array_3[1] & 0xf0) >> 4);
            char_array_4[2] = ((char_array_3[1] & 0x0f) << 2) + ((char_array_3[2] & 0xc0) >> 6);
            char_array_4[3] = char_array_3[2] & 0x3f;
            for (size_t j = 0; j < 4; j++) encoded += base64_chars[char_array_4[j]];
            i = 0;
        }
    }
    if (i) {
        for (size_t j = i; j < 3; j++) char_array_3[j] = '\0';
        char_array_4[0] = (char_array_3[0] & 0xfc) >> 2;
        char_array_4[1] = ((char_array_3[0] & 0x03) << 4) + ((char_array_3[1] & 0xf0) >> 4);
        char_array_4[2] = ((char_array_3[1] & 0x0f) << 2) + ((char_array_3[2] & 0xc0) >> 6);
        char_array_4[3] = char_array_3[2] & 0x3f;
        for (size_t j = 0; j < i + 1; j++) encoded += base64_chars[char_array_4[j]];
        while (i++ < 3) encoded += '=';
    }
    return encoded;
}

std::string escape_json(const std::string& s) {
    std::string escaped;
    for (char c : s) {
        if (c == '\\') escaped += "\\\\";
        else if (c == '"') escaped += "\\\"";
        else if (c == '\n') escaped += "\\n";
        else if (c == '\r') escaped += "\\r";
        else if (c == '\t') escaped += "\\t";
        else escaped += c;
    }
    return escaped;
}

std::map<std::string, std::string> parse_json(const std::string& json) {
    std::map<std::string, std::string> res;
    std::regex key_value(R"regex("(\w+)":\s*"([^"]*)")regex");
    std::sregex_iterator iter(json.begin(), json.end(), key_value);
    std::sregex_iterator end;
    for (; iter != end; ++iter) {
        res[(*iter)[1]] = (*iter)[2];
    }
    return res;
}

bool in_array(const std::string& needle, const std::vector<std::string>& haystack) {
    return std::find(haystack.begin(), haystack.end(), needle) != haystack.end();
}

std::vector<std::string> dedup(const std::vector<std::string>& vec) {
    std::vector<std::string> out;
    std::set<std::string> seen;
    for (const auto& item : vec) {
        if (item.empty()) continue;
        if (seen.insert(item).second) out.push_back(item);
    }
    return out;
}

int main(int argc, char* argv[]) {
    std::string config_file = std::string(std::getenv("HOME")) + "/.gits/config";
    auto config = load_config(config_file);
    auto args = parse_args(argc, argv);

    if (args.status) {
        try {
            exec("git rev-parse --git-dir");
        } catch (...) {
            std::cerr << "Error: Not a git repository" << std::endl;
            return 1;
        }
        if (config.find("API_GATEWAY_URL") == config.end()) {
            std::cerr << "Error: API_GATEWAY_URL not set in ~/.gits/config" << std::endl;
            return 1;
        }
        if (config.find("USER_ID") == config.end()) {
            std::cerr << "Error: USER_ID not set in ~/.gits/config" << std::endl;
            return 1;
        }
        std::string api_url = config["API_GATEWAY_URL"];
        std::string user_id = config["USER_ID"];
        std::string cmd = "curl -s -w \"\\n%{http_code}\" \"" + api_url + "/status?user_id=" + user_id + "\"";
        std::string response = exec(cmd);
        size_t pos = response.find_last_of('\n');
        std::string body = response.substr(0, pos);
        std::string status_code = response.substr(pos + 1);
        if (status_code != "200") {
            std::cout << body << std::endl;
            return 1;
        }
        auto parsed = parse_json(body);
        std::cout << "Job ID: " << parsed["job_id"] << std::endl;
        std::cout << "Schedule Time: " << parsed["schedule_time"] << std::endl;
        std::cout << "Status: " << parsed["status"] << std::endl;
        return 0;
    }

    if (!args.delete_job_id.empty()) {
        try {
            exec("git rev-parse --git-dir");
        } catch (...) {
            std::cerr << "Error: Not a git repository" << std::endl;
            return 1;
        }
        if (config.find("API_GATEWAY_URL") == config.end()) {
            std::cerr << "Error: API_GATEWAY_URL not set in ~/.gits/config" << std::endl;
            return 1;
        }
        if (config.find("USER_ID") == config.end()) {
            std::cerr << "Error: USER_ID not set in ~/.gits/config" << std::endl;
            return 1;
        }
        std::string api_url = config["API_GATEWAY_URL"];
        std::string user_id = config["USER_ID"];
        std::string payload = R"(
{
    "job_id": ")" + args.delete_job_id + R"(",
    "user_id": ")" + user_id + R"("
}
)";
        std::string payload_file = "/tmp/payload_delete.json";
        std::ofstream pf(payload_file);
        pf << payload;
        pf.close();
        std::string cmd = "curl -s -w \"\\n%{http_code}\" -X POST \"" + api_url + "/delete\" -H 'Content-Type: application/json' -d @" + payload_file;
        std::string response = exec(cmd);
        size_t pos = response.find_last_of('\n');
        std::string body = response.substr(0, pos);
        std::string status_code = response.substr(pos + 1);
        if (status_code != "200") {
            std::cerr << "Error: Delete failed (status " << status_code << "). Response: " << body << std::endl;
            return 1;
        }
        std::cout << "Job deleted successfully" << std::endl;
        std::filesystem::remove(payload_file);
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

    std::regex iso_regex(R"(^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$)");
    if (!std::regex_match(args.schedule_time, iso_regex)) {
        std::cerr << "Error: Time must be in ISO 8601 UTC format: YYYY-MM-DDTHH:MM:SSZ (e.g. 2025-07-17T15:00:00Z)" << std::endl;
        return 1;
    }

    std::string utc_time = args.schedule_time;
    std::tm tm = {};
    std::istringstream ss(utc_time);
    ss >> std::get_time(&tm, "%Y-%m-%dT%H:%M:%SZ");
    if (ss.fail()) {
        std::cerr << "Error: Invalid time format." << std::endl;
        return 1;
    }
    std::time_t sched_t = timegm(&tm);
    std::time_t now_t = std::time(nullptr);
    if (sched_t <= now_t) {
        std::cerr << "Error: Schedule time must be in the future." << std::endl;
        return 1;
    }

    try {
        std::string git_check = exec("git rev-parse --is-inside-work-tree");
        if (trim(git_check).empty()) throw std::runtime_error("");
    } catch (...) {
        std::cerr << "Error: Must be run inside a Git repository." << std::endl;
        return 1;
    }

    std::string repo_url;
    try {
        repo_url = trim(exec("git remote get-url origin"));
    } catch (...) {
        std::cerr << "Error: Could not retrieve repository URL. Ensure 'origin' remote is set." << std::endl;
        return 1;
    }

    if (repo_url.substr(0, 8) != "https://") {
        std::cerr << "Error: Repository URL must be HTTPS." << std::endl;
        std::cerr << "Update your remote URL to HTTPS format using: git remote set-url origin <https-url>" << std::endl;
        return 1;
    }

    std::time_t epoch_ts = std::time(nullptr);
    std::string list_file = "/tmp/gits-modified-files.txt";
    std::string manifest_file = "/tmp/.gits-manifest-" + std::to_string(epoch_ts) + ".json";
    std::string manifest_repo_copy = ".gits-manifest-" + std::to_string(epoch_ts) + ".json";
    std::string zip_file = "/tmp/gits-changes-" + std::to_string(epoch_ts) + ".zip";

    auto cleanup = [&]() {
        std::filesystem::remove(list_file);
        std::filesystem::remove(zip_file);
        std::filesystem::remove(manifest_file);
        std::filesystem::remove(manifest_repo_copy);
    };

    std::string git_status = exec("git status --porcelain -M");
    std::vector<std::string> deleted_paths;
    std::vector<std::string> rename_olds;
    std::vector<std::string> rename_news;
    std::stringstream ss_git(git_status);
    std::string line;
    while (std::getline(ss_git, line)) {
        if (line.size() < 3) continue;
        char x = line[0];
        char y = line[1];
        if (x == 'D' || y == 'D') {
            std::string p = line.substr(3);
            deleted_paths.push_back(p);
        }
        if (x == 'R' || y == 'R') {
            std::string rest = line.substr(3);
            size_t arrow = rest.find(" -> ");
            if (arrow != std::string::npos) {
                std::string old_p = rest.substr(0, arrow);
                std::string new_p = rest.substr(arrow + 4);
                rename_olds.push_back(old_p);
                rename_news.push_back(new_p);
            }
        }
    }

    std::vector<std::string> files_to_zip;
    if (!args.files.empty()) {
        for (const auto& f : args.files) {
            if (std::filesystem::exists(f)) {
                files_to_zip.push_back(f);
            } else if (in_array(f, deleted_paths) || in_array(f, rename_olds) || in_array(f, rename_news)) {
                // ok
            } else {
                std::cerr << "Error: file not found: " << f << std::endl;
                return 1;
            }
        }
    } else {
        std::string porcelain = exec("git status --porcelain");
        std::stringstream ss_porcelain(porcelain);
        while (std::getline(ss_porcelain, line)) {
            if (line.size() < 3) continue;
            char x = line[0];
            char y = line[1];
            if ((x == '?' && y == '?') || (x == ' ' && y == 'M') || (x == 'M' && y == ' ')) {
                std::string p = line.substr(3);
                files_to_zip.push_back(p);
            }
        }
        for (size_t i = 0; i < rename_news.size(); ++i) {
            const auto& new_p = rename_news[i];
            if (std::filesystem::exists(new_p) && !in_array(new_p, files_to_zip)) {
                files_to_zip.push_back(new_p);
            }
        }
        if (files_to_zip.empty() && deleted_paths.empty() && rename_olds.empty()) {
            std::cout << "No changes found." << std::endl;
            return 1;
        }
    }

    std::vector<std::string> deletes_for_manifest;
    if (!args.files.empty()) {
        for (const auto& d : deleted_paths) {
            if (in_array(d, args.files)) {
                deletes_for_manifest.push_back(d);
            }
        }
        for (size_t i = 0; i < rename_olds.size(); ++i) {
            const auto& old_p = rename_olds[i];
            const auto& new_p = rename_news[i];
            if (in_array(old_p, args.files) && in_array(new_p, args.files)) {
                if (std::filesystem::exists(new_p) && !in_array(new_p, files_to_zip)) {
                    files_to_zip.push_back(new_p);
                }
                deletes_for_manifest.push_back(old_p);
            }
        }
    } else {
        deletes_for_manifest = deleted_paths;
        for (const auto& old_p : rename_olds) {
            deletes_for_manifest.push_back(old_p);
        }
    }

    files_to_zip = dedup(files_to_zip);
    deletes_for_manifest = dedup(deletes_for_manifest);

    std::ofstream list_stream(list_file);
    for (const auto& f : files_to_zip) {
        list_stream << f << std::endl;
    }

    std::string manifest = "{\n  \"deleted\": [\n";
    for (size_t i = 0; i < deletes_for_manifest.size(); ++i) {
        std::string p = deletes_for_manifest[i];
        std::string escaped;
        for (char c : p) {
            if (c == '"') escaped += "\\\"";
            else if (c == '\\') escaped += "\\\\";
            else escaped += c;
        }
        manifest += "    \"" + escaped + "\"";
        if (i < deletes_for_manifest.size() - 1) manifest += ",";
        manifest += "\n";
    }
    manifest += "  ]\n}";

    std::ofstream manifest_stream(manifest_file);
    manifest_stream << manifest;
    manifest_stream.close();

    std::filesystem::copy(manifest_file, manifest_repo_copy);

    list_stream << manifest_repo_copy << std::endl;
    list_stream.close();

    std::string zip_cmd = "zip -r \"" + zip_file + "\" -@ < \"" + list_file + "\" > /dev/null 2>&1";
    int zip_ret = std::system(zip_cmd.c_str());
    if (zip_ret != 0) {
        std::cerr << "Error: Failed to create zip." << std::endl;
        cleanup();
        return 1;
    }

    if (config.find("API_GATEWAY_URL") == config.end()) {
        std::cerr << "Error: API_GATEWAY_URL not set in ~/.gits/config" << std::endl;
        cleanup();
        return 1;
    }
    if (config.find("AWS_GITHUB_TOKEN_SECRET") == config.end()) {
        std::cerr << "Error: AWS_GITHUB_TOKEN_SECRET not set in ~/.gits/config" << std::endl;
        cleanup();
        return 1;
    }
    if (config.find("USER_ID") == config.end()) {
        std::cerr << "Error: USER_ID not set in ~/.gits/config" << std::endl;
        cleanup();
        return 1;
    }

    std::string api_url = config["API_GATEWAY_URL"];
    std::string aws_github_token_secret = config["AWS_GITHUB_TOKEN_SECRET"];
    std::string user_id = config["USER_ID"];
    std::string github_user = config["GITHUB_USER"];
    std::string github_email = config["GITHUB_EMAIL"];

    std::ifstream zip_stream(zip_file, std::ios::binary);
    std::vector<unsigned char> zip_data((std::istreambuf_iterator<char>(zip_stream)), std::istreambuf_iterator<char>());
    std::string zip_b64 = base64_encode(zip_data);

    std::string cm_escaped = escape_json(args.commit_message);

    std::string payload = R"(
{
    "schedule_time": ")" + utc_time + R"(",
    "repo_url": ")" + repo_url + R"(",
    "zip_filename": ")" + std::filesystem::path(zip_file).filename().string() + R"(",
    "zip_base64": ")" + zip_b64 + R"(",
    "github_token_secret": ")" + aws_github_token_secret + R"(",
    "github_user": ")" + github_user + R"(",
    "github_email": ")" + github_email + R"(",
    "commit_message": ")" + cm_escaped + R"(",
    "user_id": ")" + user_id + R"("
}
)";

    std::string payload_file = "/tmp/payload_schedule.json";
    std::ofstream pf2(payload_file);
    pf2 << payload;
    pf2.close();

    std::string curl_cmd = "curl -s -w \"\\n%{http_code}\" -X POST \"" + api_url + "/schedule\" -H 'Content-Type: application/json' -d @" + payload_file;
    std::string response = exec(curl_cmd);
    size_t pos = response.find_last_of('\n');
    std::string body = response.substr(0, pos);
    std::string status_code = response.substr(pos + 1);
    if (status_code != "200") {
        std::cerr << "Error: Remote scheduling failed (status " << status_code << "). Response: " << body << std::endl;
        cleanup();
        std::filesystem::remove(payload_file);
        return 1;
    }

    cleanup();
    std::filesystem::remove(payload_file);
    std::cout << "Successfully scheduled" << std::endl;
    return 0;
}
