#!/bin/bash
# C3 P1: the design exam (the first of a change's two exams): two headless sessions read the documents only.
cd /home/zhijie/Desktop/github/be-assembly-standard
O=dev/rebuild/c3-data/exam-p1; echo $$ > $O/run.pid
( claude -p --setting-sources project --allowedTools Read,Grep,Glob < $O/questions.md > $O/answer-default.md 2> $O/answer-default.err; echo "EXAM DONE default $?" >> $O/run.out ) &
( claude -p --model sonnet --setting-sources project --allowedTools Read,Grep,Glob < $O/questions.md > $O/answer-sonnet.md 2> $O/answer-sonnet.err; echo "EXAM DONE sonnet $?" >> $O/run.out ) &
wait
echo "EXAM ALL-DONE" >> $O/run.out
