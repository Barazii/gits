update readme file.

stress test         <-

discuss deployment to users on their machines. installation on their machines.

make check for git repo and config variables defined at begining of program run. gits.cpp: duplicate check of current git repo

fix the names mess. 

make --status --log. make --delete --deschedule.

discuss UI

discuss gits name. make the name gisch or gis

discuss end to end encryption. conclusion: security comes from data injection at runtime. sol: cli->lambda->secrets manager->codebuild. restrict our own IAM permission to prevent viewing secrets manager values. for clients questioning, add their emails to github source code project and setup job/solution to notify them for any changes applied to the codebuild yaml file (?) or add their emails to aws account to receive notifications when changes applied to codebuild job IAM service role (?). use library to encrypt the ssh key or PAT on client local host before sending through api gateway to avoid sending those sensitive data from client machine network to gisch network on aws(?)

discuss schedule local time again. 

test on macOS