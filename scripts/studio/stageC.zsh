#!/bin/zsh
# Stage C (Mac Studio, M5 Max): the speed table. The fork's CPU engine (cg33 = published head, cg31 = installed) and the Metal engine
# on six models, paired rounds. Stock is in stage S (linked through cg33 at 18 threads).
source ${0:A:h}/common.zsh; gate "stage C"
for row in "patch 1 10500" "patch 5 1200" "notch 1 16000" "notch 3 2000" "kgcpw 1 15000" "ksma 1 6000"; do
  set -- ${=row}
  ab speed_${1}_s$2 $1 $2 $3 4 cg33@multithreaded:$T3 cg33@multithreaded:$T2 cg33@multithreaded:$T1 cg33@multithreaded:0 \
     cg31@multithreaded:$T3 cg31@multithreaded:0 cg33@metal-diamond
done
print "stage C end $(date '+%F %T')"
