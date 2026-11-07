#!/bin/bash
# Foundations item 5, T11a: the long simulation (be-sdk-go tiering/sim_test.go) on the base resources. Usage:
#   run-sim.sh <name> <minutes>   output in <name>/: sim.log (the parent's lines, SIM ...), replicas.log (their stderr)
# The last line of sim.log is "SIMRUN ALL-DONE rc=<exit>".
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")/$1; mkdir -p $O
echo $$ > $O/run.pid
. $R/dev/rebuild/experiment-scripts/itenv.sh > /dev/null 2>&1
cd $R/tools/be-sdk-go && git rev-parse --short HEAD > $O/sdk-commit.txt && git status --short >> $O/sdk-commit.txt
SIM_MINUTES=$2 SIM_REPLICA_LOG=$O/replicas.log go test -tags simulation -count=1 -timeout 0 -v \
  -run TestTheLongSimulation ./tiering/ > $O/sim.log 2>&1
echo "SIMRUN ALL-DONE rc=$?" >> $O/sim.log
