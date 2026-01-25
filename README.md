# gits - Git Scheduler

[![Python](https://img.shields.io/badge/Python-3.x-blue.svg)](https://python.org)
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![C++](https://img.shields.io/badge/C%2B%2B-17-blue.svg)](https://isocpp.org/)

> A powerful event-driven serverless command-line tool to schedule Git commands for execution at specified times

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Installation](#installation)
- [Usage](#usage)

## Overview

`gits` is a multi-level CLI utility that allows developers to schedule Git operations for execution at specific times in the future. Perfect for securing your code that you developed at a late time outside working hours, avoiding bothering your teammates by email notifications of new pushed code to the repository. This software was born out of real-life challenges of pushing code at late time when I was working a full-time developer at a company.

## Features

- **Freedom**: Schedule Git commands without worrying about the rest of the project co-developers being notified at inapproperiate times or risking the loss of your code. More interestingly, gits is serverless which means you can turn off your laptop and the code will still be commited and pushed at the specified time.
- **High Privacy**: The software is hosted on your own AWS infrastructure eliminating any chance of code files breach.
- **Cross-Platform**: Works on Linux and macOS.
- **Security**: Your code files will be stored at the world's best and most secure cloud servers - AWS.

## Architecture

Below is a high-level architecture diagram showing how gits operates across different AWS services

![gits Architecture](diagram/diagram.drawio.png)

The system leverages AWS EventBridge for scheduling, S3 for temporary code storage, CodeBuild for running Git commands automation job at the specified time, Lambda functions with API Gateway to receive commands from user's terminal, and SecretsManager for storing sensitive data such as your GitHub token and SSH deploy keys. Additionally, the app is placed in a VPC to have strict inbound and outbound data paths preventing unwanted exposure to the external internet. Moreover, the app is serverless, ensuring code changes are commited and pushed even when your local machine is offline and turned off.

## Installation

### Install and setup gits

1. **Deploy the cloud infrastructure**

Run the Python script `cloudformation/deploy-all.py` which will deploy all resources on your AWS account. For this to work, AWS CLI must be configured on your laptop. Note that it might take 3-4 hours the first time for building the docker images and pushing them to AWS ECR.

2. **Create GitHub Personal Access Token (PAT)**

The GitHub PAT allows you to push code to your repositories from a different machine/server. The steps of that should be fairly doable.

3. **Define the configuration file**

Replace the placeholders with your information and execute the following command:

   ```bash
   cat <<EOF > ~/.gits/config
   GITHUB_USERNAME=
   GITHUB_DISPLAY_NAME=
   GITHUB_EMAIL=
   GITHUB_TOKEN=
   API_GATEWAY_URL=
   API_KEY=
   EOF
   ```
Note that the variables `API_GATEWAY_URL` and `API_KEY` should not obtained from the deployed API Gateway resources.

4. **Install gits CLI system-wide**

Go to the directory `backend` and compile the code:

   ```make
   make build
   ```
Then install the produced executable:

   ```bash
   sudo make install
   ```
This allows you to run gits from any directory.

## Usage

Go to a Git directory and execute the help command to see all the three commands of gits, their arguments and their syntax:

   ```bash
   gits help
   ```

## Debugging

- When deploying the AWS infrastructure, your AWS account must have enough permissions to deploy the different resources.
- When you create GitHub PAT, make sure the required repositories are selected. Also, make sure enough permissions are included in the PAT so you can push code to the target repository from a new remote server.

---

⭐ If you find this project cool, give it a star ⭐