#!/bin/bash
# C5 P5: the consistency exam (the second of a change's two exams): two headless sessions read the changed documents
# and code and answer questions.md. Output: answer-<model>.md; "EXAM DONE <model> <exit>" lines in run.out.
cd /home/zhijie/Desktop/github/be-assembly-standard
O=dev/rebuild/c5-data/exam-p5; echo $$ > $O/run.pid
( claude -p --setting-sources project --allowedTools Read,Grep,Glob < $O/questions.md > $O/answer-default.md 2> $O/answer-default.err; echo "EXAM DONE default $?" >> $O/run.out ) &
( claude -p --model sonnet --setting-sources project --allowedTools Read,Grep,Glob < $O/questions.md > $O/answer-sonnet.md 2> $O/answer-sonnet.err; echo "EXAM DONE sonnet $?" >> $O/run.out ) &
wait
echo "EXAM ALL-DONE" >> $O/run.out
