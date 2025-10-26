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
#include <aws/dynamodb/DynamoDBClient.h>
#include <aws/dynamodb/model/PutItemRequest.h>
#include <aws/dynamodb/model/AttributeValue.h>
#include <cstdlib>
#include <iostream>
#include <chrono>
#include <ctime>
#include <iomanip>
#include <sstream>

using namespace aws::lambda_runtime;
using namespace Aws::Utils::Json;
using namespace Aws::S3;
using namespace Aws::S3::Model;
using namespace Aws::EventBridge;
using namespace Aws::EventBridge::Model;
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

JsonValue create_response(int status, const JsonValue& body) {
    JsonValue response;
    response.WithInteger("statusCode", status);
    response.WithObject("headers", JsonValue().WithString("Content-Type", "application/json"));
    response.WithString("body", body.View().WriteCompact());
    return response;
}

invocation_response lambda_handler(invocation_request const& request, S3Client& s3_client, EventBridgeClient& events_client, DynamoDBClient& dynamodb_client) {
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
        std::string github_token_secret = view.GetString("github_token_secret");
        std::string github_user = view.GetString("github_user");
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
        env_vars_vector.push_back(JsonValue().WithString("name", "GITHUB_TOKEN_SECRET").WithString("value", github_token_secret).WithString("type", "PLAINTEXT"));
        env_vars_vector.push_back(JsonValue().WithString("name", "GITHUB_USER").WithString("value", github_user).WithString("type", "PLAINTEXT"));
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

    auto handler = [&](invocation_request const& req) {
        return lambda_handler(req, s3_client, events_client, dynamodb_client);
    };

    run_handler(handler);

    Aws::ShutdownAPI(options);
    return 0;
}
