#!/bin/zsh
# usage: prof.sh <label> <cmd...>
label=$1; shift
s=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
"$@" > /tmp/perf/out/$label.stdout 2> /tmp/perf/out/$label.stderr &
pid=$!
sample $pid 300 1 -mayDie -file /tmp/perf/out/$label.sample >/dev/null 2>&1 &
spid=$!
wait $pid; st=$?
e=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
wait $spid 2>/dev/null
echo "$label exit=$st wall=$(echo "$e - $s" | bc)s"
grep -vE "^\s*$" /tmp/perf/out/$label.stderr | tail -2 | cut -c1-200
