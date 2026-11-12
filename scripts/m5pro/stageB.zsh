#!/bin/zsh
# Stage B: the tiled sweep (fork commit 0ef186b = snapshot cg32d, OPENEMS_TBLOCK) against the fused sweep of cg31.
# $1.. = the three thread counts to use (default 5 10 15).
source ${0:A:h}/common.zsh
T1=${1:-5}; T2=${2:-10}; T3=${3:-15}; S=cg32d
print "stage B start $(date '+%F %T')"; zsh $M5PRO_DIR/wait_quiet.zsh 80 6 ${GATE:-300} || print "not quiet at the start: running anyway, read the others column of every line"
H="OPENEMS_TBLOCK=auto;OPENEMS_TBLOCK_HOOKS=0"
for row in "patch 5 1000 OPENEMS_TBLOCK=4 $H" "notch 3 1500 OPENEMS_TBLOCK=8;OPENEMS_TBLOCK_W=17 $H" "cube 2 600 OPENEMS_TBLOCK=4 $H" \
           "lbox 2 400 OPENEMS_TBLOCK=3 OPENEMS_TBLOCK=2" "ksma 1 6000 OPENEMS_TBLOCK=8;OPENEMS_TBLOCK_W=17 OPENEMS_TBLOCK=8;OPENEMS_TBLOCK_W=65" \
           "lbox 1 2000 OPENEMS_TBLOCK=8;OPENEMS_TBLOCK_W=33 OPENEMS_TBLOCK=4"; do
  set -- ${=row}
  ab tiled_${1}_s$2 $1 $2 $3 3 cg31@multithreaded:$T1 cg31@multithreaded:$T2 cg31@multithreaded:$T3 \
     "$S@multithreaded:$T1#OPENEMS_TBLOCK=auto" "$S@multithreaded:$T2#OPENEMS_TBLOCK=auto" "$S@multithreaded:$T3#OPENEMS_TBLOCK=auto" \
     "$S@multithreaded:$T3#OPENEMS_TBLOCK=auto;OPENEMS_BALANCE=0" "$S@multithreaded:$T1#$4" "$S@multithreaded:$T1#$5"
done
print "stage B end $(date '+%F %T')"
