#include <iostream>
#include <string>
#include <vector>
#include <map>
#include <fstream>
#include <sstream>
#include <cstdlib>
#include <cstdio>
#include <unistd.h>
#include <getopt.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <dirent.h>
#include <regex>
#include <chrono>
#include <ctime>
#include <iomanip>
#include <algorithm>
#include <set>
#include <filesystem>

using namespace std;
using namespace filesystem;

string exec(const string& cmd) {
    char buffer[128];
    string result = "";
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) throw runtime_error("popen() failed!");
    try {
        while (fgets(buffer, sizeof buffer, pipe) != NULL) {
            result += buffer;
        }
    } catch (...) {
        pclose(pipe);
        throw;
    }
    int status = pclose(pipe);
    if (status != 0) {
        // For commands that may fail, handle accordingly
    }
    return result;
}

map<string, string> load_config() {
    map<string, string> config;
    string home = getenv("HOME");
    string config_file = home + "/.gits/config";
    ifstream file(config_file);
    if (file.is_open()) {
        string line;
        while (getline(file, line)) {
            size_t pos = line.find('=');
            if (pos != string::npos) {
                string key = line.substr(0, pos);
                string value = line.substr(pos + 1);
                config[key] = value;
            }
        }
        file.close();
    }
    return config;
}

struct Args {
    string schedule_time;
    string commit_message;
    vector<string> files;
    bool status_arg = false;
    string delete_job_id;
};

Args parse_args(int argc, char* argv[]) {
    Args args;
    int opt;
    static struct option long_options[] = {
        {"message", required_argument, 0, 'm'},
        {"file", required_argument, 0, 'f'},
        {"help", no_argument, 0, 'h'},
        {"status", no_argument, 0, 's'},
        {"delete", required_argument, 0, 'd'},
        {0, 0, 0, 0}
    };
    int option_index = 0;
    while ((opt = getopt_long(argc, argv, "m:f:hsd:", long_options, &option_index)) != -1) {
        switch (opt) {
            case 'm':
                if (optarg == nullptr) {
                    cerr << "Error: -m|--message requires a commit message" << endl;
                    exit(2);
                }
                args.commit_message = optarg;
                break;
            case 'f':
                if (optarg == nullptr) {
                    cerr << "Error: -f|--file requires a file path" << endl;
                    exit(2);
                }
                {
                    string files_str = optarg;
                    stringstream ss(files_str);
                    string file;
                    while (getline(ss, file, ',')) {
                        if (!file.empty()) {
                            args.files.push_back(file);
                        }
                    }
                }
                break;
            case 'h':
                cout << "Usage: gits <schedule-time> [-m|--message \"commit message\"] [-f|--file <path>]..." << endl;
                cout << "       gits --status" << endl;
                cout << "       gits --delete <job_id>" << endl;
                cout << "Examples:" << endl;
                cout << "  gits '2025-07-17T15:00:00Z' -m 'Fix: docs'" << endl;
                cout << "  gits '2025-07-17T15:00:00Z' -f app.py -f README.md" << endl;
                cout << "  gits '2025-07-17T15:00:00Z' -f app.py,README.md" << endl;
                cout << "  gits --status" << endl;
                cout << "  gits --delete job-123" << endl;
                exit(0);
            case 's':
                args.status_arg = true;
                break;
            case 'd':
                if (optarg == nullptr) {
                    cerr << "Error: --delete requires a job_id" << endl;
                    exit(2);
                }
                args.delete_job_id = optarg;
                break;
            default:
                cerr << "Error: unexpected argument" << endl;
                exit(2);
        }
    }
    if (optind < argc) {
        args.schedule_time = argv[optind++];
    }
    if (optind < argc) {
        cerr << "Error: unexpected argument: " << argv[optind] << endl;
        exit(2);
    }
    return args;
}

int main(int argc, char* argv[]) {
    Args args = parse_args(argc, argv);
    auto config = load_config();

    if (args.status_arg) {
        if (system("git rev-parse --git-dir > /dev/null 2>&1") != 0) {
            cerr << "Error: Not a git repository" << endl;
            return 1;
        }
        string api_url = config["API_GATEWAY_URL"];
        if (api_url.empty()) {
            cerr << "Error: API_GATEWAY_URL not set in ~/.gits/config" << endl;
            return 1;
        }
        string user_id = config["USER_ID"];
        if (user_id.empty()) {
            cerr << "Error: USER_ID not set in ~/.gits/config" << endl;
            return 1;
        }
        string cmd = "curl -s -w \"\\n%{http_code}\" \"" + api_url + "/status?user_id=" + user_id + "\"";
        string response = exec(cmd);
        size_t last_nl = response.find_last_of('\n');
        if (last_nl == string::npos) {
            cout << response << endl;
            return 1;
        }
        string body = response.substr(0, last_nl);
        string status_code = response.substr(last_nl + 1);
        if (status_code != "200") {
            cout << body << endl;
            return 1;
        }
        // Assuming jq is available, but to avoid, parse manually or assume JSON
        // For simplicity, use exec with jq
        string schedule_time = exec("echo '" + body + "' | jq -r '.schedule_time' 2>/dev/null");
        schedule_time.erase(schedule_time.find_last_not_of(" \n\r\t") + 1);
        string status_str = exec("echo '" + body + "' | jq -r '.status' 2>/dev/null");
        status_str.erase(status_str.find_last_not_of(" \n\r\t") + 1);
        string job_id = exec("echo '" + body + "' | jq -r '.job_id' 2>/dev/null");
        job_id.erase(job_id.find_last_not_of(" \n\r\t") + 1);
        cout << "Job ID: " << job_id << endl;
        cout << "Schedule Time: " << schedule_time << endl;
        cout << "Status: " << status_str << endl;
        return 0;
    }

    if (!args.delete_job_id.empty()) {
        if (system("git rev-parse --git-dir > /dev/null 2>&1") != 0) {
            cerr << "Error: Not a git repository" << endl;
            return 1;
        }
        string api_url = config["API_GATEWAY_URL"];
        if (api_url.empty()) {
            cerr << "Error: API_GATEWAY_URL not set in ~/.gits/config" << endl;
            return 1;
        }
        string user_id = config["USER_ID"];
        if (user_id.empty()) {
            cerr << "Error: USER_ID not set in ~/.gits/config" << endl;
            return 1;
        }
        string payload = "{\"job_id\": \"" + args.delete_job_id + "\", \"user_id\": \"" + user_id + "\"}";
        string cmd = "curl -s -w \"\\n%{http_code}\" -X POST \"" + api_url + "/delete\" -H 'Content-Type: application/json' -d '" + payload + "'";
        string response = exec(cmd);
        size_t last_nl = response.find_last_of('\n');
        if (last_nl == string::npos) {
            cerr << "Error: Delete failed. Response: " << response << endl;
            return 1;
        }
        string body = response.substr(0, last_nl);
        string status_code = response.substr(last_nl + 1);
        if (status_code != "200") {
            cerr << "Error: Delete failed (status " << status_code << "). Response: " << body << endl;
            return 1;
        }
        cout << "Job deleted successfully" << endl;
        return 0;
    }

    if (args.schedule_time.empty()) {
        cerr << "Error: Schedule time required." << endl;
        cerr << "Usage: gits <schedule-time> [-m|--message \"commit message\"] [-f|--file <path>]..." << endl;
        cerr << "Example:" << endl;
        cerr << "  gits '2025-07-17T15:00:00Z' -m 'Fix: docs'" << endl;
        cerr << "  gits '2025-07-17T15:00:00Z' -f app.py -f README.md" << endl;
        cerr << "  gits '2025-07-17T15:00:00Z' -f app.py,README.md" << endl;
        return 1;
    }

    regex iso_regex(R"(^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$)");
    if (!regex_match(args.schedule_time, iso_regex)) {
        cerr << "Error: Time must be in ISO 8601 UTC format: YYYY-MM-DDTHH:MM:SSZ (e.g. 2025-07-17T15:00:00Z)" << endl;
        return 1;
    }

    string utc_ts_str = exec("date -u -d '" + args.schedule_time + "' +%s 2>/dev/null");
    utc_ts_str.erase(utc_ts_str.find_last_not_of(" \n\r\t") + 1);
    if (utc_ts_str.empty()) {
        cerr << "Error: Invalid time format." << endl;
        return 1;
    }
    long utc_ts = stol(utc_ts_str);
    long current = time(nullptr);
    if (utc_ts <= current) {
        cerr << "Error: Schedule time must be in the future." << endl;
        return 1;
    }

    if (system("git rev-parse --is-inside-work-tree > /dev/null 2>&1") != 0) {
        cerr << "Error: Must be run inside a Git repository." << endl;
        return 1;
    }

    string repo_url = exec("git remote get-url origin 2>/dev/null");
    repo_url.erase(repo_url.find_last_not_of(" \n\r\t") + 1);
    if (repo_url.empty()) {
        cerr << "Error: Could not retrieve repository URL. Ensure 'origin' remote is set." << endl;
        return 1;
    }
    if (repo_url.find("https://") != 0) {
        cerr << "Error: Repository URL must be HTTPS." << endl;
        cerr << "Update your remote URL to HTTPS format using: git remote set-url origin <https-url>" << endl;
        return 1;
    }

    string git_status = exec("git status --porcelain -M");
    vector<string> deleted_paths;
    vector<string> rename_olds;
    vector<string> rename_news;
    stringstream ss_status(git_status);
    string line;
    while (getline(ss_status, line)) {
        if (line.size() < 3) continue;
        char x = line[0];
        char y = line[1];
        if (x == 'D' || y == 'D') {
            string p = line.substr(3);
            deleted_paths.push_back(p);
        }
        if (x == 'R' || y == 'R') {
            string rest = line.substr(3);
            size_t arrow = rest.find(" -> ");
            if (arrow != string::npos) {
                string old_p = rest.substr(0, arrow);
                string new_p = rest.substr(arrow + 4);
                rename_olds.push_back(old_p);
                rename_news.push_back(new_p);
            }
        }
    }

    auto in_array = [](const string& needle, const vector<string>& haystack) {
        return find(haystack.begin(), haystack.end(), needle) != haystack.end();
    };

    vector<string> files_to_zip;
    if (!args.files.empty()) {
        for (const string& f : args.files) {
            if (exists(f)) {
                files_to_zip.push_back(f);
            } else if (in_array(f, deleted_paths) || in_array(f, rename_olds) || in_array(f, rename_news)) {
                // ok
            } else {
                cerr << "Error: file not found: " << f << endl;
                return 1;
            }
        }
    } else {
        string porcelain = exec("git status --porcelain");
        stringstream ss_porcelain(porcelain);
        while (getline(ss_porcelain, line)) {
            if (line.size() < 2) continue;
            if (line.substr(0, 2) == "??") {
                string f = line.substr(3);
                files_to_zip.push_back(f);
            } else if (line.substr(0, 2) == " M" || line.substr(0, 2) == "M ") {
                string f = line.substr(3);
                files_to_zip.push_back(f);
            }
        }
        for (const string& n : rename_news) {
            if (exists(n) && !in_array(n, files_to_zip)) {
                files_to_zip.push_back(n);
            }
        }
        if (files_to_zip.empty() && deleted_paths.empty() && rename_olds.empty()) {
            cout << "No changes found." << endl;
            return 1;
        }
    }

    vector<string> deletes_for_manifest;
    if (!args.files.empty()) {
        for (const string& d : deleted_paths) {
            if (in_array(d, args.files)) {
                deletes_for_manifest.push_back(d);
            }
        }
        for (size_t i = 0; i < rename_olds.size(); ++i) {
            string old_p = rename_olds[i];
            string new_p = rename_news[i];
            if (in_array(old_p, args.files) && in_array(new_p, args.files)) {
                if (exists(new_p) && !in_array(new_p, files_to_zip)) {
                    files_to_zip.push_back(new_p);
                }
                deletes_for_manifest.push_back(old_p);
            }
        }
    } else {
        deletes_for_manifest = deleted_paths;
        for (const string& o : rename_olds) {
            deletes_for_manifest.push_back(o);
        }
    }

    set<string> unique_files(files_to_zip.begin(), files_to_zip.end());
    files_to_zip.assign(unique_files.begin(), unique_files.end());
    set<string> unique_deletes(deletes_for_manifest.begin(), deletes_for_manifest.end());
    deletes_for_manifest.assign(unique_deletes.begin(), unique_deletes.end());

    string epoch_ts = to_string(time(nullptr));
    string manifest_file = "/tmp/.gits-manifest-" + epoch_ts + ".json";
    string manifest_repo_copy = ".gits-manifest-" + epoch_ts + ".json";

    ofstream mf(manifest_file);
    mf << "{" << endl;
    mf << "  \"deleted\": [" << endl;
    for (size_t i = 0; i < deletes_for_manifest.size(); ++i) {
        mf << "    \"" << deletes_for_manifest[i] << "\"";
        if (i < deletes_for_manifest.size() - 1) mf << ",";
        mf << endl;
    }
    mf << "  ]" << endl;
    mf << "}" << endl;
    mf.close();

    copy(manifest_file, manifest_repo_copy);

    string list_file = "/tmp/gits-modified-files.txt";
    ofstream lf(list_file);
    if (!files_to_zip.empty()) {
        for (const string& f : files_to_zip) {
            lf << f << endl;
        }
    }
    lf << manifest_repo_copy << endl;
    lf.close();

    string zip_file = "/tmp/gits-changes-" + to_string(time(nullptr)) + ".zip";
    string zip_cmd = "zip -r '" + zip_file + "' -@ < '" + list_file + "' > /dev/null 2>&1";
    if (system(zip_cmd.c_str()) != 0) {
        cerr << "Error: Failed to create zip." << endl;
        remove(list_file.c_str());
        remove(zip_file.c_str());
        remove(manifest_file.c_str());
        remove(manifest_repo_copy.c_str());
        return 1;
    }

    string zip_b64 = exec("base64 -w 0 '" + zip_file + "' 2>/dev/null");
    zip_b64.erase(zip_b64.find_last_not_of(" \n\r\t") + 1);
    if (zip_b64.empty()) {
        cerr << "Error: Failed to base64 encode zip file." << endl;
        remove(list_file.c_str());
        remove(zip_file.c_str());
        remove(manifest_file.c_str());
        remove(manifest_repo_copy.c_str());
        return 1;
    }

    string cm_escaped = args.commit_message;
    // Escape for JSON
    // Simple replace
    size_t pos = 0;
    while ((pos = cm_escaped.find("\\", pos)) != string::npos) {
        cm_escaped.replace(pos, 1, "\\\\");
        pos += 2;
    }
    pos = 0;
    while ((pos = cm_escaped.find("\"", pos)) != string::npos) {
        cm_escaped.replace(pos, 1, "\\\"");
        pos += 2;
    }
    pos = 0;
    while ((pos = cm_escaped.find("\n", pos)) != string::npos) {
        cm_escaped.replace(pos, 1, "\\n");
        pos += 2;
    }
    pos = 0;
    while ((pos = cm_escaped.find("\r", pos)) != string::npos) {
        cm_escaped.replace(pos, 1, "\\r");
        pos += 2;
    }
    pos = 0;
    while ((pos = cm_escaped.find("\t", pos)) != string::npos) {
        cm_escaped.replace(pos, 1, "\\t");
        pos += 2;
    }

    string payload = "{";
    payload += "\"schedule_time\": \"" + args.schedule_time + "\",";
    payload += "\"repo_url\": \"" + repo_url + "\",";
    payload += "\"zip_filename\": \"" + path(zip_file).filename().string() + "\",";
    payload += "\"zip_base64\": \"" + zip_b64 + "\",";
    payload += "\"github_token_secret\": \"" + config["AWS_GITHUB_TOKEN_SECRET"] + "\",";
    payload += "\"github_user\": \"" + config["GITHUB_USER"] + "\",";
    payload += "\"github_email\": \"" + config["GITHUB_EMAIL"] + "\",";
    payload += "\"commit_message\": \"" + cm_escaped + "\",";
    payload += "\"user_id\": \"" + config["USER_ID"] + "\"";
    payload += "}";

    string api_url = config["API_GATEWAY_URL"];
    if (api_url.empty()) {
        cerr << "Error: API_GATEWAY_URL not set in ~/.gits/config" << endl;
        remove(list_file.c_str());
        remove(zip_file.c_str());
        remove(manifest_file.c_str());
        remove(manifest_repo_copy.c_str());
        return 1;
    }
    string token_secret = config["AWS_GITHUB_TOKEN_SECRET"];
    if (token_secret.empty()) {
        cerr << "Error: AWS_GITHUB_TOKEN_SECRET not set in ~/.gits/config" << endl;
        remove(list_file.c_str());
        remove(zip_file.c_str());
        remove(manifest_file.c_str());
        remove(manifest_repo_copy.c_str());
        return 1;
    }
    string user_id = config["USER_ID"];
    if (user_id.empty()) {
        cerr << "Error: USER_ID not set in ~/.gits/config" << endl;
        remove(list_file.c_str());
        remove(zip_file.c_str());
        remove(manifest_file.c_str());
        remove(manifest_repo_copy.c_str());
        return 1;
    }

    string curl_cmd = "curl -s -w \"\\n%{http_code}\" -X POST \"" + api_url + "/schedule\" -H 'Content-Type: application/json' -d '" + payload + "'";
    string response = exec(curl_cmd);
    size_t last_nl = response.find_last_of('\n');
    if (last_nl == string::npos) {
        cerr << "Error: Remote scheduling failed. Response: " << response << endl;
        remove(list_file.c_str());
        remove(zip_file.c_str());
        remove(manifest_file.c_str());
        remove(manifest_repo_copy.c_str());
        return 1;
    }
    string body = response.substr(0, last_nl);
    string status_code = response.substr(last_nl + 1);
    if (status_code != "200") {
        cerr << "Error: Remote scheduling failed (status " << status_code << "). Response: " << body << endl;
        remove(list_file.c_str());
        remove(zip_file.c_str());
        remove(manifest_file.c_str());
        remove(manifest_repo_copy.c_str());
        return 1;
    }

    remove(list_file.c_str());
    remove(zip_file.c_str());
    remove(manifest_file.c_str());
    remove(manifest_repo_copy.c_str());
    cout << "Successfully scheduled" << endl;
    return 0;
}