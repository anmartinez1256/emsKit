#!/bin/zsh
# Stage A (Mac Studio, M5 Max): memory bandwidth (STREAM, the standalone fused kernel, the shared-tile kernel), then the thread sweep
# 1..18 + auto of the fork's CPU engine (cg33) on three models.
source ${0:A:h}/common.zsh; gate "stage A"
{ for T in 1 $T1 $T2 $T3; do
    print "== STREAM threads $T  $(date +%T)  all processes cpu% $(load)"
    OMP_NUM_THREADS=$T ${STREAM_BINARY:?} | grep -E "^(Copy|Scale|Add|Triad|Solution)"
  done } > $O/stream.txt 2>&1
grep -E "^==|^Triad" $O/stream.txt | cut -c1-90
for i in 1 2 3; do print "== kb_idx fused, run $i $(date +%T) all processes cpu% $(load)"; KB_THREADS=$T1,$T2,$T3 KB_FUSED=1 ${KB_IDX:?} 8; done > $O/kb_idx_fused.txt 2>&1
grep -E "^==|fused, |stock, 1" $O/kb_idx_fused.txt | cut -c1-90
{ print "== kb_tile $(date +%T) all processes cpu% $(load)"; KB_THREADS=$T1,$T2,$T3 ${KB_TILE:?}; } > $O/kb_tile.txt 2>&1
grep -E "threads:|best|MISMATCH" $O/kb_tile.txt | cut -c1-150 | head -12
CFG=(); for T in $(seq 1 18); do CFG+=(cg33@multithreaded:$T); done; CFG+=(cg33@multithreaded:0)
ab threads_notch_s3 notch 3 2000 3 $CFG
ab threads_patch_s5 patch 5 1200 3 $CFG
ab threads_kgcpw kgcpw 1 15000 3 $CFG
for f in ab_notch_s3_n2000 ab_patch_s5_n1200 ab_kgcpw_s1_n15000; do
  print "auto pick $f: $(grep -h 'Best performance found using' $OPENEMS_BENCH_RUNS/$f/c18/r*/openEMS.log 2>/dev/null | grep -oE '[0-9]+ threads' | tr '\n' ' ')"
done
print "stage A end $(date '+%F %T')"
