#!/bin/zsh
# The Mac Studio speed set, one quiet block (about 120 min): stages C, S, A, E, B, D, most wanted first.
O=${STUDIO_OUT:?set STUDIO_OUT to an output folder}; here=${0:A:h}; mkdir -p $O/logs
print "studio set start $(date '+%F %T'); $(uptime)"
( while true; do print "$(date +%T) all $(ps -A -o %cpu= | awk '{s+=$1} END{printf "%.0f", s}') %"; sleep 10; done ) > $O/load_all.log 2>&1 &
lp=$!
for s in C S A E B D; do zsh $here/stage$s.zsh > $O/logs/stage$s.out 2>&1; print "stage $s exit $? $(date +%T)"; tail -2 $O/logs/stage$s.out | cut -c1-160; done
kill $lp 2>/dev/null
print "studio set end $(date '+%F %T')"
