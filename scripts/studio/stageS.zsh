#!/bin/zsh
# Stage S (Mac Studio, M5 Max): the stock v0.37.0 baseline at 1, 2, 3, 4, 6, 8, 12 and 18 threads on the six models (fixed counts, no
# tuner), with cg33 at 18 threads as the link to stage C. Half the steps of stage C.
source ${0:A:h}/common.zsh; gate "stage S"
for row in "patch 1 5000" "patch 5 600" "notch 1 8000" "notch 3 1000" "kgcpw 1 7500" "ksma 1 3000"; do
  set -- ${=row}
  ab stock_${1}_s$2 $1 $2 $3 3 stock@multithreaded:1 stock@multithreaded:2 stock@multithreaded:3 stock@multithreaded:4 \
     stock@multithreaded:6 stock@multithreaded:8 stock@multithreaded:12 stock@multithreaded:18 cg33@multithreaded:$T3
done
print "stage S end $(date '+%F %T')"
