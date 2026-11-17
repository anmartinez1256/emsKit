#!/bin/zsh
# wait_quiet.zsh LIMIT NEED MAXWAIT: returns 0 once the CPU use of all processes has been below LIMIT % (of one core) in
# NEED samples in a row, 20 s apart; returns 3 after MAXWAIT seconds without that. Prints one line either way.
LIM=${1:-80}; NEED=${2:-6}; MAX=${3:-3600}; t0=$SECONDS; ok=0; c=0
while (( SECONDS - t0 < MAX )); do
  c=$(ps -A -o %cpu= | awk '{s+=$1} END{printf "%d", s}')
  if (( c < LIM )); then ok=$((ok+1)); else ok=0; fi
  if (( ok >= NEED )); then print "QUIET $(date '+%F %T') all processes ${c}% after $((SECONDS-t0)) s"; exit 0; fi
  sleep 20
done
print "BUSY $(date '+%F %T') all processes ${c}% after $((SECONDS-t0)) s:"; ps -A -o %cpu=,pid=,comm= -r | head -5 | cut -c1-120
exit 3
