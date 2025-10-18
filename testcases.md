what are manual test cases?

1. use arg --message but dont pass message. expect: success execution. codebuild default commit message is used.
2. use arg --file but dont pass file. expect: error and exit.
3. use arg --file with passed files comma-separated and space-separated and plus-separated. expect: ?
4. dont pass time. expect: error and exit.
5. pass time arg not as first arg. expect: error and exit.
6. wrong format time. expect: error and exit.
7. pass time in the past. expect: error and exit. 
8. run in non git repository.
9. run in git repo but not http.
10. use --file arg with staged and unstaged deleted files. expect: success
11. use --file arg and pass files. expect: success.
12. use --file and pass a non existing file. expect: error and exit.
13. dont use arg --file with staged and unstaged files. expect: success.  
14. use duplicate arg --message. expect: ?
15. use arg --file with duplicate files. expect: success. 
16. schedule 2 posts at same time. expect: success