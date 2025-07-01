Revised Architecture
Docker on Lambda Approach

Using a Docker container in Lambda is an excellent solution for your git operations
This approach gives you more control over the environment and dependencies
You can pre-install git and any other required tools in your Docker image
Remember that Lambda container images can be up to 10GB, but there's still a 15-minute execution time limit
Notification System

Since you prefer email notifications, Amazon SNS (Simple Notification Service) is the ideal choice
Lambda can publish to SNS topics upon completion of git operations
You can configure SNS to send emails with detailed success/failure information
Consider adding message formatting to make the emails more readable with operation details
Core Architecture Components

Local CLI tool → DynamoDB (command storage)
EventBridge (time-based trigger) → Lambda with Docker container (execution)
Lambda → SNS (email notifications)
Security Enhancements

AWS Secrets Manager is still recommended for securely storing git credentials
This eliminates the need to embed credentials in your Docker image or pass them through DynamoDB