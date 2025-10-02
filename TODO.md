Pass github pat secret name as env variable when setting the codebuild in the backend.

Pass commit message as env variable when setting the codebuild in the backend.

Send WhatsApp notis for success or fail.

Support commiting grouped files together. Still only one command gits [TIMESTAMP] [FILES TO BE ADDED TOGETHER] [COMMIT MESSAGE]. If no files passed, then take all the modified files. If no commit message passed, take current message as default. This will need handling in the backend when creating the event bridge for multiple jobs scheduled. 

Find a way to enter username and email for github in the yaml file. Maybe also env variables to codebuild.

automate the deployment of lambda code.

automate the unit test of the lambda code.