#!/bin/zsh
# STREAM and the free-space cube sweep of results/common_benchmarks_2026-11-10.txt.
#   usage: run.zsh OUT_DIR STREAM_BINARY        (from the repository root; python3 with the openEMS module)
# STREAM_BINARY: McCalpin's stream.c 5.10 built with OpenMP, 100 M elements, 20 passes, e.g.
#   clang -O3 -mcpu=native -Xclang -fopenmp -I$(brew --prefix libomp)/include -DSTREAM_ARRAY_SIZE=100000000 \
#     -DNTIMES=20 stream.c -o stream -L$(brew --prefix libomp)/lib -lomp
# Snapshots `stock` and `cg29` as bench/bench.py expects them. Cube: N = 100, 150, 200, 300, 400 cells per edge.
O=${1:?OUT_DIR}; S=${2:?STREAM_BINARY}; mkdir -p $O
for T in 1 4 8 10; do
  print "== STREAM threads $T  $(date +%T)  all processes cpu% $(ps -A -o %cpu= | awk '{s+=$1} END{printf "%.0f",s}')"
  OMP_NUM_THREADS=$T $S | grep -E "^(Copy|Scale|Add|Triad|Solution)"
done > $O/stream.txt 2>&1
for row in "1 6000" "1.5 1800" "2 800" "3 600" "4 600"; do
  s=${row% *}; n=${row#* }
  if (( s >= 3 )); then ST=(stock@multithreaded:8); else ST=(stock@multithreaded:4 stock@multithreaded:8); fi
  python3 bench/abtest.py cube --scale $s --nrts $n --rounds 3 --quiet 150 --quiet-max 1200 --run-redo 1 \
    --configs $ST cg29@multithreaded:4 cg29@multithreaded:8 cg29@metal-diamond --out $O/cube_s$s.txt
done
