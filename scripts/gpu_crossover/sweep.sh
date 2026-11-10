#!/bin/zsh
# The GPU-against-CPU size sweep of 2026-11-05 (results/gpu_crossover_cg29_2026-11-05.txt): bench/abtest.py on every point
# below, 4 paired rounds of the multithreaded engine at 8 and 4 threads, the metal-diamond engine, and the metal-diamond
# engine with OPENEMS_DIAMOND_TIMING=1. Usage: sweep.sh LIB OUT_DIR [MODEL:SCALE:STEPS ...]
#   LIB = a snapshot name for bench.py (cg29 for the published run), OUT_DIR gets out/ (abtest records) and runs/;
#   without points it runs the published list (the three passes of that day, in one go). Needs RFSIM_PATH for kgcpw.
# Afterwards: tiles.py OUT_DIR/tiles with the same points, analyze.py OUT_DIR > OUT_DIR/analysis.txt, then
# mkresult.py OUT_DIR RESULT_FILE (it also reads out_pass1/ and out_len/, made by hand; see its docstring).
LIB=$1 X=${2:A} B=${0:A:h}/../../bench; shift 2
(( $# )) || set -- notch:1:14000 notch:1.25:7500 notch:1.5:4500 notch:2:3000 notch:2.5:3000 notch:3:3000 \
  patch:1:36500 patch:1.25:21000 patch:1.5:13000 patch:1.75:9000 patch:2:6000 patch:2.5:3500 patch:3:3000 patch:3.5:3000 \
  patch:4:3000 patch:5:3000 kgcpw:2:36000 kgcpw:1.3:24500 kgcpw:1:15500 kgcpw:0.8:9000 kgcpw:0.65:6000 kgcpw:0.5:3000 \
  kgcpw:0.4:3000 kgcpw:0.35:3000 kgcpw:0.3:3000
(caffeinate -i -w $$ &)
mkdir -p $X/out $X/runs
for P in "$@"; do
  IFS=: read M S N <<< "$P"
  echo "=== $M scale $S nrts $N  $(date '+%F %T')"
  python3 $B/abtest.py $M --scale $S --nrts $N --rounds 4 \
    --configs $LIB@multithreaded:8 $LIB@multithreaded:4 $LIB@metal-diamond "$LIB@metal-diamond#OPENEMS_DIAMOND_TIMING=1" \
    --runs $X/runs --out $X/out/${M}_s${S}_n${N}.txt --quiet 150 --quiet-max 1800 --run-redo 3
  echo "=== exit $?  $(date '+%F %T')"
done
echo "=== sweep done $(date '+%F %T')"
