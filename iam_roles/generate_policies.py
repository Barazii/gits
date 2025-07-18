import json
import os
import sys

config_path = os.path.expanduser("~/.gits/config")

try:
    CONFIG = {}
    with open(config_path, "r") as f:
        for line in f:
            line = line.strip()
            if "=" in line and not line.startswith("#"):
                key, value = line.split("=", 1)
                CONFIG[key.strip()] = value.strip()
except FileNotFoundError:
    print(f"Config file not found at {config_path}")
    sys.exit(1)
except Exception as e:
    print(f"Error reading config file: {e}")
    sys.exit(1)


def generate_eventbridge_trust_policy():
    """Generate EventBridge trust policy with dynamic values"""
    policy = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {"Service": "events.amazonaws.com"},
                "Action": "sts:AssumeRole",
            }
        ],
    }
    return policy


def generate_codebuild_policy():
    """Generate codebuild permission policy with dynamic values"""
    policy = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": ["s3:GetObject", "s3:ListBucket"],
                "Resource": [
                    f"arn:aws:s3:::{CONFIG['AWS_BUCKET_NAME']}/*",
                    f"arn:aws:s3:::{CONFIG['AWS_BUCKET_NAME']}",
                ],
            },
            {
                "Effect": "Allow",
                "Action": ["secretsmanager:GetSecretValue"],
                "Resource": f"arn:aws:secretsmanager:{CONFIG['AWS_REGION']}:{CONFIG['AWS_ACCOUNT_ID']}:secret:{CONFIG['AWS_GITHUB_TOKEN_SECRET']}-*",
            },
            {
                "Effect": "Allow",
                "Action": [
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                "Resource": "*",
            },
        ],
    }
    return policy


def generate_eventbridge_policy():
    """Generate EventBridge permission policy with dynamic values"""
    policy = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": "codebuild:StartBuild",
                "Resource": f"arn:aws:codebuild:{CONFIG['AWS_REGION']}:{CONFIG['AWS_ACCOUNT_ID']}:project/{CONFIG['AWS_CODEBUILD_PROJECT_NAME']}",
            }
        ],
    }
    return policy


def main():
    policy1 = generate_eventbridge_policy()
    policy2 = generate_codebuild_policy()
    policy3 = generate_eventbridge_trust_policy()

    # Write to files
    output_file = "eventbridge-trust-policy.json"
    with open(output_file, "w") as f:
        json.dump(policy3, f, indent=2)

    output_file = "codebuild-permission-policy.json"
    with open(output_file, "w") as f:
        json.dump(policy2, f, indent=2)

    output_file = "eventbridge-permission-policy.json"
    with open(output_file, "w") as f:
        json.dump(policy1, f, indent=2)


if __name__ == "__main__":
    main()
