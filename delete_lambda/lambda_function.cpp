#include <aws/lambda-runtime/runtime.h>
#include <aws/core/Aws.h>
#include <aws/core/utils/json/JsonSerializer.h>
#include <aws/core/utils/base64/Base64.h>
#include <aws/eventbridge/EventBridgeClient.h>
#include <aws/eventbridge/model/RemoveTargetsRequest.h>
#include <aws/eventbridge/model/DeleteRuleRequest.h>
#include <aws/dynamodb/DynamoDBClient.h>
#include <aws/dynamodb/model/QueryRequest.h>
#include <aws/dynamodb/model/DeleteItemRequest.h>
#include <aws/dynamodb/model/AttributeValue.h>
#include <cstdlib>
#include <iostream>
#include <string>

using namespace aws::lambda_runtime;
using namespace Aws::Utils::Json;
using namespace Aws::EventBridge;
using namespace Aws::EventBridge::Model;
using namespace Aws::DynamoDB;
using namespace Aws::DynamoDB::Model;

JsonValue create_response(int status, const JsonValue& body) {
    JsonValue response;
    response.WithInteger("statusCode", status);
    response.WithObject("headers", JsonValue().WithString("Content-Type", "application/json"));
    response.WithString("body", body.View().WriteCompact());
    return response;
}

invocation_response lambda_handler(invocation_request const& request, EventBridgeClient& events_client, DynamoDBClient& dynamodb_client) {
    try {
        std::cout << "Received event: " << request.payload << std::endl;
        JsonValue event_json(request.payload);
        if (!event_json.WasParseSuccessful()) {
            std::cerr << "Failed to parse event JSON" << std::endl;
            return invocation_response::failure("Failed to parse event JSON", "ParseError");
        }

        std::string body_raw = event_json.View().GetString("body");
        bool is_base64 = event_json.View().GetBool("isBase64Encoded");

        if (is_base64) {
            std::cout << "Decoding base64 body" << std::endl;
            Aws::Utils::Base64::Base64 base64;
            Aws::Utils::CryptoBuffer decoded = base64.Decode(body_raw);
            body_raw = std::string(reinterpret_cast<char*>(decoded.GetUnderlyingData()), decoded.GetLength());
        }

        JsonValue data(body_raw);
        if (!data.WasParseSuccessful()) {
            std::cerr << "Failed to parse body JSON" << std::endl;
            return invocation_response::failure("Failed to parse body JSON", "ParseError");
        }

        auto view = data.View();
        std::string job_id = view.GetString("job_id");
        std::string user_id = view.GetString("user_id");

        std::cout << "Extracted job_id: " << job_id << ", user_id: " << user_id << std::endl;

        if (job_id.empty() || user_id.empty()) {
            std::cerr << "job_id and user_id are required" << std::endl;
            JsonValue error_body;
            error_body.WithString("error", "job_id and user_id are required");
            return invocation_response::success(create_response(400, error_body).View().WriteCompact(), "application/json");
        }

        std::string region = getenv("AWS_APP_REGION");
        std::string table_name = getenv("DYNAMODB_TABLE") ? getenv("DYNAMODB_TABLE") : "";
        if (table_name.empty()) {
            std::cerr << "DYNAMODB_TABLE environment variable not set" << std::endl;
            JsonValue error_body;
            error_body.WithString("error", "DYNAMODB_TABLE environment variable not set");
            return invocation_response::success(create_response(500, error_body).View().WriteCompact(), "application/json");
        }

        // Query DynamoDB item
        std::cout << "Querying DynamoDB for job_id: " << job_id << ", user_id: " << user_id << std::endl;
        try {
            // Query to find the item with matching job_id
            QueryRequest query_request;
            query_request.SetTableName(table_name);
            Aws::String key_condition = "user_id = :user_id";
            query_request.SetKeyConditionExpression(key_condition);
            AttributeValue user_id_attr;
            user_id_attr.SetS(user_id);
            query_request.AddExpressionAttributeValues(":user_id", user_id_attr);
            Aws::String filter_expression = "job_id = :job_id";
            query_request.SetFilterExpression(filter_expression);
            AttributeValue job_id_attr;
            job_id_attr.SetS(job_id);
            query_request.AddExpressionAttributeValues(":job_id", job_id_attr);

            auto query_outcome = dynamodb_client.Query(query_request);
            if (!query_outcome.IsSuccess()) {
                std::cerr << "Failed to query DynamoDB: " << query_outcome.GetError().GetMessage() << std::endl;
                JsonValue error_body;
                error_body.WithString("error", "Failed to query DynamoDB: " + query_outcome.GetError().GetMessage());
                return invocation_response::success(create_response(500, error_body).View().WriteCompact(), "application/json");
            }

            auto& items = query_outcome.GetResult().GetItems();
            if (items.empty()) {
                std::cerr << "Job not found" << std::endl;
                JsonValue error_body;
                error_body.WithString("error", "Job not found");
                return invocation_response::success(create_response(404, error_body).View().WriteCompact(), "application/json");
            }

            auto& item = items[0];
            std::string added_at = item.at("added_at").GetN();
            std::string status = item.at("status").GetS();

            // Check if job is pending
            if (status != "pending") {
                std::cerr << "Cannot unschedule a job that is not pending. Current status: " << status << std::endl;
                JsonValue error_body;
                error_body.WithString("error", "Cannot unschedule a job that is not pending");
                return invocation_response::success(create_response(400, error_body).View().WriteCompact(), "application/json");
            }

            // Only if pending, remove the CodeBuild target job (EventBridge rule)
            std::cout << "Deleting EventBridge rule: " << job_id << std::endl;
            try {
                // First remove targets
                RemoveTargetsRequest remove_targets_request;
                remove_targets_request.SetRule(job_id);
                remove_targets_request.SetIds({"Target1"});
                remove_targets_request.SetForce(true);
                auto remove_outcome = events_client.RemoveTargets(remove_targets_request);
                if (!remove_outcome.IsSuccess()) {
                    std::cerr << "Warning: Failed to remove targets: " << remove_outcome.GetError().GetMessage() << std::endl;
                }

                // Then delete the rule
                DeleteRuleRequest delete_rule_request;
                delete_rule_request.SetName(job_id);
                delete_rule_request.SetForce(true);
                auto delete_outcome = events_client.DeleteRule(delete_rule_request);
                if (!delete_outcome.IsSuccess()) {
                    if (delete_outcome.GetError().GetErrorType() == EventBridgeErrors::RESOURCE_NOT_FOUND) {
                        std::cerr << "Rule " << job_id << " not found" << std::endl;
                    } else {
                        std::cerr << "Failed to delete EventBridge rule: " << delete_outcome.GetError().GetMessage() << std::endl;
                        JsonValue error_body;
                        error_body.WithString("error", "Failed to delete EventBridge rule: " + delete_outcome.GetError().GetMessage());
                        return invocation_response::success(create_response(500, error_body).View().WriteCompact(), "application/json");
                    }
                } else {
                    std::cout << "Deleted EventBridge rule: " << job_id << std::endl;
                }
            } catch (const std::exception& e) {
                std::cerr << "Error deleting rule: " << e.what() << std::endl;
                JsonValue error_body;
                error_body.WithString("error", std::string("Error deleting rule: ") + e.what());
                return invocation_response::success(create_response(500, error_body).View().WriteCompact(), "application/json");
            }

            // Delete the item from DynamoDB
            std::cout << "Deleting DynamoDB item: user_id=" << user_id << ", added_at=" << added_at << std::endl;
            DeleteItemRequest delete_request;
            delete_request.SetTableName(table_name);
            AttributeValue pk_user_id;
            pk_user_id.SetS(user_id);
            AttributeValue sk_added_at;
            sk_added_at.SetN(added_at);
            delete_request.AddKey("user_id", pk_user_id);
            delete_request.AddKey("added_at", sk_added_at);

            auto delete_outcome = dynamodb_client.DeleteItem(delete_request);
            if (!delete_outcome.IsSuccess()) {
                std::cerr << "Failed to delete DynamoDB item: " << delete_outcome.GetError().GetMessage() << std::endl;
                JsonValue error_body;
                error_body.WithString("error", "Failed to delete DynamoDB item: " + delete_outcome.GetError().GetMessage());
                return invocation_response::success(create_response(500, error_body).View().WriteCompact(), "application/json");
            }

            std::cout << "Deleted DynamoDB item: user_id=" << user_id << ", job_id=" << job_id << std::endl;
        } catch (const std::exception& e) {
            std::cerr << "Error deleting DB item: " << e.what() << std::endl;
            JsonValue error_body;
            error_body.WithString("error", std::string("Error deleting DB item: ") + e.what());
            return invocation_response::success(create_response(500, error_body).View().WriteCompact(), "application/json");
        }

        std::cout << "Job unscheduled successfully" << std::endl;
        JsonValue success_body;
        success_body.WithString("message", "Job unscheduled successfully");
        return invocation_response::success(create_response(200, success_body).View().WriteCompact(), "application/json");

    } catch (const std::exception& e) {
        std::cerr << "Unexpected error: " << e.what() << std::endl;
        JsonValue error_body;
        error_body.WithString("error", std::string("Unexpected error: ") + e.what());
        return invocation_response::success(create_response(500, error_body).View().WriteCompact(), "application/json");
    }
}

int main() {
    Aws::SDKOptions options;
    Aws::InitAPI(options);

    Aws::Client::ClientConfiguration config;
    config.region = getenv("AWS_APP_REGION");

    EventBridgeClient events_client(config);
    DynamoDBClient dynamodb_client(config);

    auto handler = [&](invocation_request const& req) {
        return lambda_handler(req, events_client, dynamodb_client);
    };

    run_handler(handler);

    Aws::ShutdownAPI(options);
    return 0;
}
