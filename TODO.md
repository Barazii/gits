Send WhatsApp notis for success or fail.

automate the unit test of the lambda code.

update readme file.

add support to ssh repo (not only http)

retrieving logic (tagging, user sessions and grok discussion). print all events associated with user id. but show only newest 3 like git history. then workflow take each event name and use that as job name to retrieve jobs status. then return to user terminal. Each schedule produces persistent record in ~/.gits/jobs.jsonl. rule_name embeds job_id so you can reconstruct. From rule tags get job_id (and user_id). Query CodeBuild builds for the project, then find the build whose environment variable JOB_ID == that job_id. Read its buildStatus (SUCCEEDED, FAILED, IN_PROGRESS, STOPPED, TIMED_OUT).