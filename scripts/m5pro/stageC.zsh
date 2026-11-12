#!/bin/zsh
# Stage C: the speed table. Stock v0.37.0, the fork's CPU engine, the fork's Metal engine, six models, paired rounds.
# $1 $2 $3 = thread counts (default 5 10 15); `:0` = the engine picks.
source ${0:A:h}/common.zsh
T1=${1:-5}; T2=${2:-10}; T3=${3:-15}
print "stage C start $(date '+%F %T')"; zsh $M5PRO_DIR/wait_quiet.zsh 80 6 ${GATE:-300} || print "not quiet at the start: running anyway, read the others column of every line"
for row in "patch 1 10500" "patch 5 1200" "notch 1 16000" "notch 3 2000" "kgcpw 1 15000" "ksma 1 6000"; do
  set -- ${=row}
  ab speed_${1}_s$2 $1 $2 $3 5 stock@multithreaded:$T1 stock@multithreaded:$T2 cg31@multithreaded:$T1 cg31@multithreaded:$T2 \
     cg31@multithreaded:$T3 cg31@multithreaded:0 cg31@metal-diamond
done
print "stage C end $(date '+%F %T')"
