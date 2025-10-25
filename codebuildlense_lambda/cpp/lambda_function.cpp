#include <aws/lambda-runtime/runtime.h>
#include <aws/core/Aws.h>
#include <aws/core/utils/json/JsonSerializer.h>
#include <aws/codebuild/CodeBuildClient.h>
#include <aws/codebuild/model/BatchGetBuildsRequest.h>
#include <aws/dynamodb/DynamoDBClient.h>
#include <aws/dynamodb/model/QueryRequest.h>
#include <aws/dynamodb/model/UpdateItemRequest.h>
#include <aws/dynamodb/model/AttributeValue.h>
#include <cstdlib>
#include <iostream>
#include <string>

using namespace aws::lambda_runtime;
using namespace Aws::Utils::Json;
using namespace Aws::CodeBuild;
using namespace Aws::CodeBuild::Model;
using namespace Aws::DynamoDB;
using namespace Aws::DynamoDB::Model;

JsonValue create_response(int status, const std::string& body) {
    JsonValue response;
    response.WithInteger("statusCode", status);
    response.WithString("body", body);
    return response;
}

invocation_response lambda_handler(invocation_request const& request, CodeBuildClient& codebuild_client, DynamoDBClient& dynamodb_client) {
    try {
        std::cout << "Received event: " << request.payload << std::endl;
        JsonValue event_json(request.payload);
        if (!event_json.WasParseSuccessful()) {
            std::cerr << "Failed to parse event JSON" << std::endl;
            return invocation_response::failure("Failed to parse event JSON", "ParseError");
        }

        auto event_view = event_json.View();
        auto detail = event_view.GetObject("detail");
        std::string build_id = detail.GetString("build-id");
        std::string build_status = detail.GetString("build-status");

        std::cout << "Extracted build_id: " << build_id << ", build_status: " << build_status << std::endl;

        if (build_id.empty() || build_status.empty()) {
            std::cerr << "Missing build-id or build-status in event" << std::endl;
            return invocation_response::success(create_response(400, "Invalid event").View().WriteCompact(), "application/json");
        }

        // Get build details
        std::cout << "Getting build details for build_id: " << build_id << std::endl;
        BatchGetBuildsRequest batch_request;
        batch_request.SetIds({build_id});
        auto batch_outcome = codebuild_client.BatchGetBuilds(batch_request);
        if (!batch_outcome.IsSuccess() || batch_outcome.GetResult().GetBuilds().empty()) {
            std::cerr << "No build found for id: " << build_id << std::endl;
            return invocation_response::success(create_response(404, "Build not found").View().WriteCompact(), "application/json");
        }

        auto build = batch_outcome.GetResult().GetBuilds()[0];
        auto env_vars = build.GetEnvironment().GetEnvironmentVariables();

        // Extract user_id
        std::string user_id;
        for (const auto& var : env_vars) {
            if (var.GetName() == "USER_ID") {
                user_id = var.GetValue();
                break;
            }
        }

        std::cout << "Extracted user_id: " << user_id << std::endl;

        if (user_id.empty()) {
            std::cerr << "USER_ID not found in build environment variables" << std::endl;
            return invocation_response::success(create_response(400, "USER_ID not found").View().WriteCompact(), "application/json");
        }

        std::string table_name = getenv("DYNAMODB_TABLE") ? getenv("DYNAMODB_TABLE") : "";
        if (table_name.empty()) {
            std::cerr << "DYNAMODB_TABLE environment variable not set" << std::endl;
            return invocation_response::success(create_response(500, "Configuration error").View().WriteCompact(), "application/json");
        }

        // Query for the most recent item
        std::cout << "Querying DynamoDB for user_id: " << user_id << std::endl;
        QueryRequest query_request;
        query_request.SetTableName(table_name);
        Aws::String key_condition = "user_id = :user_id";
        query_request.SetKeyConditionExpression(key_condition);
        AttributeValue user_id_attr;
        user_id_attr.SetS(user_id);
        query_request.AddExpressionAttributeValues(":user_id", user_id_attr);
        query_request.SetScanIndexForward(false);
        query_request.SetLimit(1);

        auto query_outcome = dynamodb_client.Query(query_request);
        if (!query_outcome.IsSuccess() || query_outcome.GetResult().GetItems().empty()) {
            std::cerr << "No item found for user " << user_id << std::endl;
            return invocation_response::success(create_response(404, "No item found").View().WriteCompact(), "application/json");
        }

        auto item = query_outcome.GetResult().GetItems()[0];
        std::string added_at = item.at("added_at").GetN();

        // Update the status
        std::cout << "Updating status for user " << user_id << " to " << build_status << std::endl;
        UpdateItemRequest update_request;
        update_request.SetTableName(table_name);
        AttributeValue pk_user_id;
        pk_user_id.SetS(user_id);
        AttributeValue sk_added_at;
        sk_added_at.SetN(added_at);
        update_request.AddKey("user_id", pk_user_id);
        update_request.AddKey("added_at", sk_added_at);
        update_request.SetUpdateExpression("SET #s = :val");
        update_request.AddExpressionAttributeNames("#s", "status");
        AttributeValue status_attr;
        status_attr.SetS(build_status);
        update_request.AddExpressionAttributeValues(":val", status_attr);

        auto update_outcome = dynamodb_client.UpdateItem(update_request);
        if (!update_outcome.IsSuccess()) {
            std::cerr << "Error updating DynamoDB: " << update_outcome.GetError().GetMessage() << std::endl;
            return invocation_response::success(create_response(500, "Internal error").View().WriteCompact(), "application/json");
        }

        std::cout << "Successfully updated status for user " << user_id << std::endl;
        return invocation_response::success(create_response(200, "Success").View().WriteCompact(), "application/json");

    } catch (const std::exception& e) {
        std::cerr << "Error processing event: " << e.what() << std::endl;
        return invocation_response::success(create_response(500, "Internal error").View().WriteCompact(), "application/json");
    }
}

int main() {
    Aws::SDKOptions options;
    Aws::InitAPI(options);

    Aws::Client::ClientConfiguration config;
    config.region = getenv("AWS_APP_REGION") ? getenv("AWS_APP_REGION") : "eu-north-1";

    CodeBuildClient codebuild_client(config);
    DynamoDBClient dynamodb_client(config);

    auto handler = [&](invocation_request const& req) {
        return lambda_handler(req, codebuild_client, dynamodb_client);
    };

    run_handler(handler);

    Aws::ShutdownAPI(options);
    return 0;
}
