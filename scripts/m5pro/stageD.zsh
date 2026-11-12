#!/bin/zsh
# Stage D: the allocation-placement valley on this chip and macOS 27.2.1, and three scheduling knobs at all threads.
source ${0:A:h}/common.zsh
print "stage D start $(date '+%F %T')"; zsh $M5PRO_DIR/wait_quiet.zsh 80 6 ${GATE:-300} || print "not quiet at the start: running anyway, read the others column of every line"
ab valley_kgcpw kgcpw 1 15000 4 cg31@multithreaded:1 "cg31@multithreaded:1#OPENEMS_NO_STAGGER=1" cg31@multithreaded:5 \
   "cg31@multithreaded:5#OPENEMS_NO_STAGGER=1" stock@multithreaded:1 stock@multithreaded:5
ab knobs_notch_s3 notch 3 2000 4 cg31@multithreaded:15 "cg31@multithreaded:15#OPENEMS_FLAGS=0" \
   "cg31@multithreaded:15#OPENEMS_FLAGS_SPIN_US=50" "cg31@multithreaded:15#OPENEMS_QOS=0" \
   cg31@multithreaded:10 "cg31@multithreaded:10#OPENEMS_FLAGS=0" "cg31@multithreaded:10#OPENEMS_QOS=0"
print "stage D end $(date '+%F %T')"
