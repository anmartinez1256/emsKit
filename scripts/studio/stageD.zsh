#!/bin/zsh
# Stage D (Mac Studio, M5 Max): the allocation-placement valley on this chip and macOS 27.0, and the scheduling knobs at all threads.
source ${0:A:h}/common.zsh; gate "stage D"
ab valley_kgcpw kgcpw 1 15000 3 cg33@multithreaded:1 "cg33@multithreaded:1#OPENEMS_NO_STAGGER=1" cg33@multithreaded:$T1 \
   "cg33@multithreaded:$T1#OPENEMS_NO_STAGGER=1" stock@multithreaded:1
ab knobs_notch_s3 notch 3 2000 3 cg33@multithreaded:$T3 "cg33@multithreaded:$T3#OPENEMS_FLAGS=0" "cg33@multithreaded:$T3#OPENEMS_QOS=0" \
   "cg33@multithreaded:0#OPENEMS_TUNE_START=p"
print "stage D end $(date '+%F %T')"
