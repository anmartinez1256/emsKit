#!/bin/zsh
# Stage A: memory bandwidth (STREAM, the standalone fused kernel, the shared-tile kernel), then the thread sweep 1..15 of the
# fork's CPU engine (snapshot cg31) on three models. STREAM_BINARY: McCalpin's stream.c 5.10 with OpenMP, 100 M elements,
# 20 passes (build line in ../common_bench/run.zsh); KB_IDX, KB_TILE: binaries of ../kernel/kb_idx.cpp and kb_tile.cpp.
source ${0:A:h}/common.zsh
print "stage A start $(date '+%F %T')"; zsh $M5PRO_DIR/wait_quiet.zsh 80 6 ${GATE:-300} || print "not quiet at the start: running anyway, read the others column of every line"
{ for T in 1 5 10 15; do
    print "== STREAM threads $T  $(date +%T)  all processes cpu% $(load)"
    OMP_NUM_THREADS=$T ${STREAM_BINARY:?} | grep -E "^(Copy|Scale|Add|Triad|Solution)"
  done } > $O/stream.txt 2>&1
grep -E "^==|^Triad" $O/stream.txt | cut -c1-90
for i in 1 2 3; do print "== kb_idx fused, run $i $(date +%T) all processes cpu% $(load)"; KB_FUSED=1 KB_THREADS=1,5,10,15 ${KB_IDX:?} 8; done > $O/kb_idx_fused.txt 2>&1
grep -E "^==|fused, |stock, 1" $O/kb_idx_fused.txt | cut -c1-90
{ print "== kb_tile $(date +%T) all processes cpu% $(load)"; KB_THREADS=5,10,15 ${KB_TILE:?}; } > $O/kb_tile.txt 2>&1
grep -E "threads:|best|MISMATCH" $O/kb_tile.txt | cut -c1-150 | head -12
CFG=(); for T in $(seq 1 15); do CFG+=(cg31@multithreaded:$T); done; CFG+=(cg31@multithreaded:0)
ab threads_notch_s3 notch 3 2000 4 $CFG
ab threads_patch_s5 patch 5 1200 4 $CFG
ab threads_kgcpw kgcpw 1 15000 4 $CFG
# the thread count the engine's own choice (config c15 = cg31@multithreaded:0) settled on, per round
for f in ab_notch_s3_n2000 ab_patch_s5_n1200 ab_kgcpw_s1_n15000; do
  print "auto pick $f: $(grep -h 'Best performance found using' $OPENEMS_BENCH_RUNS/$f/c15/r*/openEMS.log 2>/dev/null | grep -oE '[0-9]+ threads' | tr '\n' ' ')"
done
print "stage A end $(date '+%F %T')"
