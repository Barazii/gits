what are manual test cases?

1. use arg --message but dont pass message. expect: success execution. codebuild default commit message is used.    (DONE)

2. use arg --file but dont pass file. expect: error and exit.   (DONE)

3. use arg --file with passed files comma-separated and space-separated and plus-separated. expect: ?   (DONE)

run gits workflow and pass files that had no changed. expect: nothing.  (DONE)

4. dont pass time. expect: error and exit.  (DONE)

5. pass time arg not as first arg. expect: error and exit.  (DONE)

6. wrong format time. expect: error and exit.   (DONE)

7. pass time in the past. expect: error and exit.   (DONE)

8. run in non git repository.   (DONE)

9. run in git repo but not http.    (DONE)

10. use --file arg with staged and unstaged deleted files. expect: success  (DONE)

11. use --file arg and pass files. expect: success. (DONE)

12. use --file and pass a non existing file. expect: error and exit.    (DONE)

13. dont use arg --file with staged and unstaged files. expect: success.    (DONE)

14. use duplicate arg --message. expect: ?  (DONE)

15. use arg --file with duplicate files. expect: success.(DONE)

16. schedule 2 posts at same time. expect: success  (DONE)

shedule more than one job, then retrieve and check retrieving order.    (DONE)