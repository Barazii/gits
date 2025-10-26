#include <aws/core/Aws.h>
#include <aws/lambda-runtime/runtime.h>
#include <aws/dynamodb/DynamoDBClient.h>
#include <aws/dynamodb/model/QueryRequest.h>
#include <aws/dynamodb/model/AttributeValue.h>
#include <aws/core/utils/json/JsonSerializer.h>
#include <aws/core/utils/logging/LogLevel.h>
#include <aws/core/utils/logging/ConsoleLogSystem.h>
#include <aws/core/utils/logging/LogMacros.h>
#include <iostream>
#include <string>
#include <cstdlib>

using namespace aws::lambda_runtime;
using namespace Aws::DynamoDB;
using namespace Aws::DynamoDB::Model;
using namespace Aws::Utils::Json;
using namespace Aws::Utils::Logging;

static invocation_response my_handler(invocation_request const& request)
{
    std::cout << "Lambda handler started" << std::endl;
    std::cout << "Received event: " << request.payload << std::endl;
    JsonValue event(request.payload);
    if (!event.WasParseSuccessful()) {
        std::cerr << "Failed to parse JSON" << std::endl;
        JsonValue fullResponse;
        fullResponse.WithInteger("statusCode", 400);
        fullResponse.WithString("body", JsonValue().WithString("error", "Invalid JSON").View().WriteReadable());
        return invocation_response::success(fullResponse.View().WriteReadable(), "application/json");
    }
    std::cout << "Event JSON parsed successfully" << std::endl;

    JsonView eventView = event.View();
    auto queryParams = eventView.GetObject("queryStringParameters");
    if (!queryParams.IsObject()) {
        std::cerr << "Missing queryStringParameters" << std::endl;
        JsonValue fullResponse;
        fullResponse.WithInteger("statusCode", 400);
        fullResponse.WithString("body", JsonValue().WithString("error", "Missing queryStringParameters").View().WriteReadable());
        return invocation_response::success(fullResponse.View().WriteReadable(), "application/json");
    }
    std::cout << "queryStringParameters found" << std::endl;

    std::string user_id = queryParams.GetString("user_id");
    if (user_id.empty()) {
        std::cerr << "user_id is required" << std::endl;
        JsonValue fullResponse;
        fullResponse.WithInteger("statusCode", 400);
        fullResponse.WithString("body", JsonValue().WithString("error", "user_id is required").View().WriteReadable());
        return invocation_response::success(fullResponse.View().WriteReadable(), "application/json");
    }
    std::cout << "Extracted user_id: " << user_id << std::endl;

    const char* region_env = std::getenv("AWS_APP_REGION");
    std::string region = region_env ? region_env : "eu-north-1";
    std::cout << "Using region: " << region << std::endl;

    const char* table_env = std::getenv("DYNAMODB_TABLE");
    if (!table_env) {
        std::cerr << "DYNAMODB_TABLE environment variable not set" << std::endl;
        JsonValue fullResponse;
        fullResponse.WithInteger("statusCode", 500);
        fullResponse.WithString("body", JsonValue().WithString("error", "DYNAMODB_TABLE environment variable not set").View().WriteReadable());
        return invocation_response::success(fullResponse.View().WriteReadable(), "application/json");
    }

    std::string table_name = table_env;
    std::cout << "Using table: " << table_name << std::endl;

    Aws::Client::ClientConfiguration clientConfig;
    clientConfig.region = region;
    DynamoDBClient dynamoClient(clientConfig);
    std::cout << "DynamoDB client initialized" << std::endl;

    QueryRequest queryRequest;
    queryRequest.SetTableName(table_name);
    Aws::String keyCondition = "user_id = :user_id";
    queryRequest.SetKeyConditionExpression(keyCondition);
    AttributeValue userIdAttr;
    userIdAttr.SetS(user_id);
    queryRequest.AddExpressionAttributeValues(":user_id", userIdAttr);
    queryRequest.SetScanIndexForward(false);
    queryRequest.SetLimit(1);

    std::cout << "Querying DynamoDB for user_id: " << user_id << std::endl;
    auto queryOutcome = dynamoClient.Query(queryRequest);
    if (!queryOutcome.IsSuccess()) {
        std::cerr << "DynamoDB query failed: " << queryOutcome.GetError().GetMessage() << std::endl;
        JsonValue fullResponse;
        fullResponse.WithInteger("statusCode", 500);
        fullResponse.WithString("body", JsonValue().WithString("error", "Internal server error").View().WriteReadable());
        return invocation_response::success(fullResponse.View().WriteReadable(), "application/json");
    }
    std::cout << "DynamoDB query successful" << std::endl;

    auto& items = queryOutcome.GetResult().GetItems();
    if (items.empty()) {
        std::cout << "No items found for user_id: " << user_id << std::endl;
        JsonValue fullResponse;
        fullResponse.WithInteger("statusCode", 404);
        fullResponse.WithString("body", JsonValue().WithString("error", "No scheduled jobs found for this user").View().WriteReadable());
        return invocation_response::success(fullResponse.View().WriteReadable(), "application/json");
    }
    std::cout << "Found " << items.size() << " item(s) for user_id: " << user_id << std::endl;

    auto& item = items[0];
    JsonValue body;
    if (item.count("job_id")) {
        body.WithString("job_id", item.at("job_id").GetS());
    }
    if (item.count("schedule_time")) {
        body.WithString("schedule_time", item.at("schedule_time").GetS());
    }
    if (item.count("status")) {
        body.WithString("status", item.at("status").GetS());
    }
    std::cout << "Response body prepared" << std::endl;

    std::cout << "Returning success for user_id: " << user_id << std::endl;
    JsonValue fullResponse;
    fullResponse.WithInteger("statusCode", 200);
    fullResponse.WithString("body", body.View().WriteReadable());
    std::cout << "Lambda handler completed successfully" << std::endl;
    return invocation_response::success(fullResponse.View().WriteReadable(), "application/json");
}

int main()
{
    Aws::Utils::Logging::InitializeAWSLogging(Aws::MakeShared<Aws::Utils::Logging::ConsoleLogSystem>("lambda", Aws::Utils::Logging::LogLevel::Info));
    Aws::SDKOptions options;
    options.loggingOptions.logLevel = Aws::Utils::Logging::LogLevel::Info;
    Aws::InitAPI(options);
    {
        run_handler(my_handler);
    }
    Aws::ShutdownAPI(options);
    Aws::Utils::Logging::ShutdownAWSLogging();
    return 0;
}
