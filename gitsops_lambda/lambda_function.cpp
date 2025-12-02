#include <aws/lambda-runtime/runtime.h>
#include <aws/core/Aws.h>
#include <aws/core/utils/json/JsonSerializer.h>
#include <aws/core/utils/memory/stl/SimpleStringStream.h>
#include <aws/core/utils/DateTime.h>
#include <aws/core/utils/base64/Base64.h>
#include <aws/s3/S3Client.h>
#include <aws/s3/model/PutObjectRequest.h>
#include <aws/eventbridge/EventBridgeClient.h>
#include <aws/eventbridge/model/PutRuleRequest.h>
#include <aws/eventbridge/model/PutTargetsRequest.h>
#include <aws/secretsmanager/SecretsManagerClient.h>
#include <aws/secretsmanager/model/CreateSecretRequest.h>
#include <aws/secretsmanager/model/DescribeSecretRequest.h>
#include <aws/secretsmanager/model/UpdateSecretRequest.h>
#include <aws/dynamodb/DynamoDBClient.h>
#include <aws/dynamodb/model/PutItemRequest.h>
#include <aws/dynamodb/model/AttributeValue.h>
#include <cstdlib>
#include <iostream>
#include <chrono>
#include <ctime>
#include <iomanip>
#include <sstream>
#include <openssl/evp.h>
#include <openssl/bio.h>
#include <openssl/buffer.h>

using namespace aws::lambda_runtime;
using namespace Aws::Utils::Json;
using namespace Aws::S3;
using namespace Aws::S3::Model;
using namespace Aws::EventBridge;
using namespace Aws::EventBridge::Model;
using namespace Aws::SecretsManager;
using namespace Aws::SecretsManager::Model;
using namespace Aws::DynamoDB;
using namespace Aws::DynamoDB::Model;

Aws::Utils::DateTime parse_iso8601(const std::string& ts) {
    std::string ts_utc = ts;
    if (ts.back() == 'Z') {
        ts_utc = ts.substr(0, ts.size() - 1) + "+0000";
    }
    return Aws::Utils::DateTime(ts_utc.c_str(), Aws::Utils::DateFormat::ISO_8601);
}

std::string cron_expression(const Aws::Utils::DateTime& dt) {
    std::stringstream ss;
    ss << "cron(" << dt.GetMinute() << " " << dt.GetHour() << " " << dt.GetDay() << " " << static_cast<int>(dt.GetMonth()) + 1 << " ? " << dt.GetYear() << ")";
    return ss.str();
}

// Function to decrypt a base64-encoded string using AES-256-CBC
std::string decrypt_token(const std::string& encrypted_b64, const std::string& iv_b64, const std::string& key_hex) {
    // Convert hex key to bytes
    std::string key;
    for (size_t i = 0; i < key_hex.length(); i += 2) {
        std::string byte_str = key_hex.substr(i, 2);
        key += static_cast<char>(std::stoi(byte_str, nullptr, 16));
    }
    if (key.size() != 32) {
        throw std::runtime_error("Invalid encryption key length");
    }

    // Base64 decode IV
    BIO* b64_iv = BIO_new(BIO_f_base64());
    BIO* bio_iv = BIO_new_mem_buf(iv_b64.c_str(), iv_b64.size());
    bio_iv = BIO_push(b64_iv, bio_iv);
    BIO_set_flags(bio_iv, BIO_FLAGS_BASE64_NO_NL);
    std::vector<unsigned char> iv(16);
    BIO_read(bio_iv, iv.data(), 16);
    BIO_free_all(bio_iv);

    // Base64 decode ciphertext
    BIO* b64 = BIO_new(BIO_f_base64());
    BIO* bio = BIO_new_mem_buf(encrypted_b64.c_str(), encrypted_b64.size());
    bio = BIO_push(b64, bio);
    BIO_set_flags(bio, BIO_FLAGS_BASE64_NO_NL);
    std::vector<unsigned char> ciphertext(encrypted_b64.size());
    int ciphertext_len = BIO_read(bio, ciphertext.data(), encrypted_b64.size());
    BIO_free_all(bio);

    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    if (!ctx) throw std::runtime_error("Failed to create cipher context");

    if (EVP_DecryptInit_ex(ctx, EVP_aes_256_cbc(), nullptr, reinterpret_cast<const unsigned char*>(key.c_str()), iv.data()) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        throw std::runtime_error("Failed to initialize decryption");
    }

    std::vector<unsigned char> plaintext(ciphertext_len + EVP_MAX_BLOCK_LENGTH);
    int len = 0, plaintext_len = 0;

    if (EVP_DecryptUpdate(ctx, plaintext.data(), &len, ciphertext.data(), ciphertext_len) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        throw std::runtime_error("Failed to decrypt data");
    }
    plaintext_len = len;

    if (EVP_DecryptFinal_ex(ctx, plaintext.data() + len, &len) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        throw std::runtime_error("Failed to finalize decryption");
    }
    plaintext_len += len;

    EVP_CIPHER_CTX_free(ctx);

    return std::string(reinterpret_cast<char*>(plaintext.data()), plaintext_len);
}

JsonValue create_response(int status, const JsonValue& body) {
    JsonValue response;
    response.WithInteger("statusCode", status);
    response.WithObject("headers", JsonValue().WithString("Content-Type", "application/json"));
    response.WithString("body", body.View().WriteCompact());
    return response;
}

invocation_response lambda_handler(invocation_request const& request, S3Client& s3_client, EventBridgeClient& events_client, DynamoDBClient& dynamodb_client, SecretsManagerClient& secrets_client) {
    try {
        std::cout << "Lambda handler started" << std::endl;
        JsonValue event_json(request.payload);
        if (!event_json.WasParseSuccessful()) {
            std::cerr << "Error: Failed to parse event JSON" << std::endl;
            return invocation_response::failure("Failed to parse event JSON", "ParseError");
        }
        std::cout << "Event JSON parsed successfully" << std::endl;

        std::string body_raw = event_json.View().GetString("body");
        bool is_base64 = event_json.View().GetBool("isBase64Encoded");

        if (is_base64) {
            Aws::Utils::Base64::Base64 base64;
            Aws::Utils::CryptoBuffer decoded = base64.Decode(body_raw);
            body_raw = std::string(reinterpret_cast<char*>(decoded.GetUnderlyingData()), decoded.GetLength());
        }
        std::cout << "Body decoded, is_base64: " << (is_base64 ? "true" : "false") << std::endl;

        JsonValue data(body_raw);
        if (!data.WasParseSuccessful()) {
            std::cerr << "Error: Failed to parse body JSON" << std::endl;
            return invocation_response::failure("Failed to parse body JSON", "ParseError");
        }
        std::cout << "Body JSON parsed successfully" << std::endl;

        auto view = data.View();
        std::string schedule_time = view.GetString("schedule_time");
        std::string repo_url = view.GetString("repo_url");
        std::string zip_filename = view.GetString("zip_filename");
        std::string zip_b64 = view.GetString("zip_base64");
        std::string encrypted_github_token = view.GetString("encrypted_github_token");
        std::string token_iv = view.GetString("token_iv");
        std::string github_username = view.GetString("github_username");
        std::string github_display_name = view.GetString("github_display_name");
        std::string github_email = view.GetString("github_email");
        std::string commit_message = view.GetString("commit_message");
        std::string user_id = view.GetString("user_id");
        std::cout << "Extracted fields: repo_url=" << repo_url << ", zip_filename=" << zip_filename << ", user_id=" << user_id << std::endl;

        Aws::Utils::DateTime dt;
        try {
            dt = parse_iso8601(schedule_time);
        } catch (const std::exception& e) {
            std::cerr << "Error: Invalid schedule_time: " << e.what() << std::endl;
            JsonValue error_body;
            error_body.WithString("error", std::string("Invalid schedule_time: ") + e.what());
            return invocation_response::success(create_response(400, error_body).View().WriteCompact(), "application/json");
        }
        std::cout << "Schedule time parsed: " << schedule_time << std::endl;

        std::string region = getenv("AWS_APP_REGION") ? getenv("AWS_APP_REGION") : "";
        std::string bucket = getenv("AWS_BUCKET_NAME") ? getenv("AWS_BUCKET_NAME") : "";
        std::string project = getenv("AWS_CODEBUILD_PROJECT_NAME") ? getenv("AWS_CODEBUILD_PROJECT_NAME") : "";
        std::string account_id = getenv("AWS_ACCOUNT_ID") ? getenv("AWS_ACCOUNT_ID") : "";
        std::string target_role_arn = getenv("EVENTBRIDGE_TARGET_ROLE_ARN") ? getenv("EVENTBRIDGE_TARGET_ROLE_ARN") : "";

        // Get encryption key from env
        const char* key_env = getenv("ENCRYPTION_KEY");
        if (!key_env) {
            std::cerr << "Error: ENCRYPTION_KEY not set" << std::endl;
            JsonValue error_body;
            error_body.WithString("error", "ENCRYPTION_KEY not configured");
            return invocation_response::success(create_response(500, error_body).View().WriteCompact(), "application/json");
        }
        std::string encryption_key = key_env;

        // Decrypt token
        std::string github_token;
        try {
            github_token = decrypt_token(encrypted_github_token, token_iv, encryption_key);
        } catch (const std::exception& e) {
            std::cerr << "Error decrypting token: " << e.what() << std::endl;
            JsonValue error_body;
            error_body.WithString("error", std::string("Decryption failed: ") + e.what());
            return invocation_response::success(create_response(400, error_body).View().WriteCompact(), "application/json");
        }

        // Decode zip
        Aws::Utils::Base64::Base64 base64;
        Aws::Utils::CryptoBuffer zip_bytes;
        try {
            zip_bytes = base64.Decode(zip_b64);
        } catch (const std::exception&) {
            std::cerr << "Error: zip_base64 is not valid base64" << std::endl;
            JsonValue error_body;
            error_body.WithString("error", "zip_base64 is not valid base64");
            return invocation_response::success(create_response(400, error_body).View().WriteCompact(), "application/json");
        }
        std::cout << "Zip decoded, size: " << zip_bytes.GetLength() << " bytes" << std::endl;

        // S3 key
        auto now = std::chrono::system_clock::now();
        auto now_tt = std::chrono::system_clock::to_time_t(now);
        std::string prefix = "changes-" + std::to_string(now_tt);
        std::string key = prefix + "/" + zip_filename;

        // Upload to S3
        std::cout << "Uploading to S3: bucket=" << bucket << ", key=" << key << std::endl;
        PutObjectRequest put_request;
        put_request.SetBucket(bucket);
        put_request.SetKey(key);
        std::shared_ptr<Aws::IOStream> input_data = Aws::MakeShared<Aws::StringStream>("");
        input_data->write(reinterpret_cast<char*>(zip_bytes.GetUnderlyingData()), zip_bytes.GetLength());
        put_request.SetBody(input_data);
        auto put_outcome = s3_client.PutObject(put_request);
        if (!put_outcome.IsSuccess()) {
            std::cerr << "Error: Failed to upload to S3: " << put_outcome.GetError().GetMessage() << std::endl;
            JsonValue error_body;
            error_body.WithString("error", "Failed to upload to S3: " + put_outcome.GetError().GetMessage());
            return invocation_response::success(create_response(500, error_body).View().WriteCompact(), "application/json");
        }

        std::string s3_path = "s3://" + bucket + "/" + key;
        std::cout << "S3 upload successful: " << s3_path << std::endl;

        std::string cron_expr = cron_expression(dt);
        std::string rule_name = "gits-" + std::to_string(now_tt);

        // Create secrets for GitHub token
        std::string token_secret_name;
        if (!github_token.empty()) {
            token_secret_name = "github-pat-" + github_email;
            DescribeSecretRequest describe_request;
            describe_request.SetSecretId(token_secret_name);
            auto describe_outcome = secrets_client.DescribeSecret(describe_request);
            if (!describe_outcome.IsSuccess()) {
                CreateSecretRequest token_secret_request;
                token_secret_request.SetName(token_secret_name);
                token_secret_request.SetSecretString(github_token);
                token_secret_request.SetDescription("GitHub token for gits job");
                auto token_outcome = secrets_client.CreateSecret(token_secret_request);
                if (!token_outcome.IsSuccess()) {
                    std::cerr << "Error: Failed to create token secret: " << token_outcome.GetError().GetMessage() << std::endl;
                    JsonValue error_body;
                    error_body.WithString("error", "Failed to create token secret: " + token_outcome.GetError().GetMessage());
                    return invocation_response::success(create_response(500, error_body).View().WriteCompact(), "application/json");
                }
                std::cout << "Token secret created: " << token_secret_name << std::endl;
            } else {
                // Update existing secret
                UpdateSecretRequest update_request;
                update_request.SetSecretId(token_secret_name);
                update_request.SetSecretString(github_token);
                auto update_outcome = secrets_client.UpdateSecret(update_request);
                if (!update_outcome.IsSuccess()) {
                    std::cerr << "Error: Failed to update token secret: " << update_outcome.GetError().GetMessage() << std::endl;
                    JsonValue error_body;
                    error_body.WithString("error", "Failed to update token secret: " + update_outcome.GetError().GetMessage());
                    return invocation_response::success(create_response(500, error_body).View().WriteCompact(), "application/json");
                }
                std::cout << "Token secret updated" << std::endl;
            }
        }

        // Put rule
        std::cout << "Creating EventBridge rule: " << rule_name << ", cron: " << cron_expr << std::endl;
        PutRuleRequest rule_request;
        rule_request.SetName(rule_name);
        rule_request.SetScheduleExpression(cron_expr);
        rule_request.SetState(RuleState::ENABLED);
        auto rule_outcome = events_client.PutRule(rule_request);
        if (!rule_outcome.IsSuccess()) {
            std::cerr << "Error: Failed to create EventBridge rule: " << rule_outcome.GetError().GetMessage() << std::endl;
            JsonValue error_body;
            error_body.WithString("error", "Failed to create EventBridge rule: " + rule_outcome.GetError().GetMessage());
            return invocation_response::success(create_response(500, error_body).View().WriteCompact(), "application/json");
        }
        std::cout << "EventBridge rule created successfully" << std::endl;

        std::string cb_project_arn = "arn:aws:codebuild:" + region + ":" + account_id + ":project/" + project;

        JsonValue input_payload;
        std::vector<JsonValue> env_vars_vector;
        env_vars_vector.push_back(JsonValue().WithString("name", "S3_PATH").WithString("value", s3_path).WithString("type", "PLAINTEXT"));
        env_vars_vector.push_back(JsonValue().WithString("name", "REPO_URL").WithString("value", repo_url).WithString("type", "PLAINTEXT"));
        env_vars_vector.push_back(JsonValue().WithString("name", "GITHUB_TOKEN_SECRET").WithString("value", token_secret_name).WithString("type", "PLAINTEXT"));
        env_vars_vector.push_back(JsonValue().WithString("name", "GITHUB_USERNAME").WithString("value", github_username).WithString("type", "PLAINTEXT"));
        env_vars_vector.push_back(JsonValue().WithString("name", "GITHUB_DISPLAY_NAME").WithString("value", github_display_name).WithString("type", "PLAINTEXT"));
        env_vars_vector.push_back(JsonValue().WithString("name", "GITHUB_EMAIL").WithString("value", github_email).WithString("type", "PLAINTEXT"));
        env_vars_vector.push_back(JsonValue().WithString("name", "COMMIT_MESSAGE").WithString("value", commit_message.empty() ? "" : commit_message).WithString("type", "PLAINTEXT"));
        env_vars_vector.push_back(JsonValue().WithString("name", "USER_ID").WithString("value", user_id).WithString("type", "PLAINTEXT"));
        Aws::Utils::Array<JsonValue> env_vars(env_vars_vector.data(), env_vars_vector.size());
        input_payload.WithArray("environmentVariablesOverride", env_vars);

        Target target;
        target.SetId("Target1");
        target.SetArn(cb_project_arn);
        target.SetInput(input_payload.View().WriteCompact());
        target.SetRoleArn(target_role_arn);

        PutTargetsRequest targets_request;
        targets_request.SetRule(rule_name);
        targets_request.SetTargets({target});
        std::cout << "Setting EventBridge targets for rule: " << rule_name << std::endl;
        auto targets_outcome = events_client.PutTargets(targets_request);
        if (!targets_outcome.IsSuccess()) {
            std::cerr << "Error: Failed to set targets: " << targets_outcome.GetError().GetMessage() << std::endl;
            JsonValue error_body;
            error_body.WithString("error", "Failed to set targets: " + targets_outcome.GetError().GetMessage());
            return invocation_response::success(create_response(500, error_body).View().WriteCompact(), "application/json");
        }
        std::cout << "EventBridge targets set successfully" << std::endl;

        // DynamoDB
        std::string table_name = getenv("DYNAMODB_TABLE") ? getenv("DYNAMODB_TABLE") : "";
        if (!table_name.empty()) {
            std::cout << "Writing to DynamoDB table: " << table_name << ", job_id: " << rule_name << std::endl;
            PutItemRequest put_item_request;
            put_item_request.SetTableName(table_name);
            AttributeValue user_id_attr;
            user_id_attr.SetS(user_id);
            AttributeValue job_id_attr;
            job_id_attr.SetS(rule_name);
            AttributeValue schedule_time_attr;
            schedule_time_attr.SetS(schedule_time);
            AttributeValue status_attr;
            status_attr.SetS("pending");
            AttributeValue added_at_attr;
            added_at_attr.SetN(std::to_string(now_tt));

            put_item_request.AddItem("user_id", user_id_attr);
            put_item_request.AddItem("job_id", job_id_attr);
            put_item_request.AddItem("schedule_time", schedule_time_attr);
            put_item_request.AddItem("status", status_attr);
            put_item_request.AddItem("added_at", added_at_attr);

            auto db_outcome = dynamodb_client.PutItem(put_item_request);
            if (!db_outcome.IsSuccess()) {
                // Log error but don't fail
                std::cerr << "Failed to write to DynamoDB: " << db_outcome.GetError().GetMessage() << std::endl;
            } else {
                std::cout << "DynamoDB write successful" << std::endl;
            }
        }

        JsonValue success_body;
        success_body.WithString("message", "Scheduled");
        success_body.WithString("rule_name", rule_name);
        success_body.WithString("cron_expression", cron_expr);
        success_body.WithString("s3_path", s3_path);
        std::cout << "Lambda handler completed successfully" << std::endl;
        return invocation_response::success(create_response(200, success_body).View().WriteCompact(), "application/json");

    } catch (const std::exception& e) {
        std::cerr << "Exception caught: " << e.what() << std::endl;
        JsonValue error_body;
        error_body.WithString("error", std::string("Exception: ") + e.what());
        return invocation_response::success(create_response(500, error_body).View().WriteCompact(), "application/json");
    }
}

int main() {
    Aws::SDKOptions options;
    Aws::InitAPI(options);

    Aws::Client::ClientConfiguration config;
    config.region = getenv("AWS_APP_REGION") ? getenv("AWS_APP_REGION") : "";

    S3Client s3_client(config);
    EventBridgeClient events_client(config);
    DynamoDBClient dynamodb_client(config);
    SecretsManagerClient secrets_client(config);

    auto handler = [&](invocation_request const& req) {
        return lambda_handler(req, s3_client, events_client, dynamodb_client, secrets_client);
    };

    run_handler(handler);

    Aws::ShutdownAPI(options);
    return 0;
}
