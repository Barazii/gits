Send WhatsApp notis for success or fail.

automate the unit test of the lambda code.

update readme file.

add support to ssh repo (not only http)

implement --status and --delete args

retrieving logic (tagging, user sessions and grok discussion). print all events associated with user id. but show only newest 3 like git history. then workflow take each event name and use that as job name to retrieve jobs status. then return to user terminal. Each schedule produces persistent record in ~/.gits/jobs.jsonl. rule_name embeds job_id so you can reconstruct. From rule tags get job_id (and user_id). Query CodeBuild builds for the project, then find the build whose environment variable JOB_ID == that job_id. Read its buildStatus (SUCCEEDED, FAILED, IN_PROGRESS, STOPPED, TIMED_OUT).

steps:
1. update the gitsops to create item in db at creation of the event bridge rule with user id schedule time and status=pending and added_at. DONE
2. update the codebuild lens lambda to not create an item, but update/edit the associated item found by user_id and then taking the most recent item by created_at. DONE
TEST
3. create new lambda function called when --status arg is used. this function execute boto3 commands to get items from dynamo db by the user id (which should be passed to lambda function) and filter them by added_at number and take the latest/most recent item and retrieve  schedule time and status from it.