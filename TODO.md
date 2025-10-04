Pass commit message as env variable when setting the codebuild in the backend.

Send WhatsApp notis for success or fail.

Support commiting grouped files together. Still only one command gits [TIMESTAMP] [FILES TO BE ADDED TOGETHER] [COMMIT MESSAGE]. If no files passed, then take all the modified files. If no commit message passed, take current message as default. This will need handling in the backend when creating the event bridge for multiple jobs scheduled. 

automate the unit test of the lambda code.

update readme file regarding the config file for setup.

handle git conflicts.

handle files created and deleted, not only changed.

add argument --file to specify which files to add. (if multiple schedules at same time what will happen?)