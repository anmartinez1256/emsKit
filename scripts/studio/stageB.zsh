#!/bin/zsh
# Stage B (Mac Studio, M5 Max): the opt-in tiled sweep (OPENEMS_TBLOCK=auto) against the fused sweep, both cg33, at 6 / 12 / 18 threads.
source ${0:A:h}/common.zsh; gate "stage B"
for row in "patch 5 1000" "notch 3 1500" "cube 2 600" "lbox 2 400" "ksma 1 6000" "lbox 1 2000"; do
  set -- ${=row}
  ab tiled_${1}_s$2 $1 $2 $3 3 cg33@multithreaded:$T1 cg33@multithreaded:$T2 cg33@multithreaded:$T3 \
     "cg33@multithreaded:$T1#OPENEMS_TBLOCK=auto" "cg33@multithreaded:$T2#OPENEMS_TBLOCK=auto" "cg33@multithreaded:$T3#OPENEMS_TBLOCK=auto"
done
print "stage B end $(date '+%F %T')"
