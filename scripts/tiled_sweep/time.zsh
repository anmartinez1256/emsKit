#!/bin/zsh
# time.zsh NEW REF OUT_DIR [T1 T2 T3]: the speed of the tiled sweep (OPENEMS_TBLOCK, snapshot NEW) against the fused sweep of
# snapshot REF, on a QUIET machine. Paired interleaved rounds of bench/abtest.py (3 per model; ROUNDS=n changes it); every line
# of a record carries the other processes' CPU and GPU use. T1 T2 T3: thread counts, default 4 8 10 (an Apple M5: the
# performance cores, 8, all); T1 also runs two more depths or widths per model. Models: patch x5, notch x3, the PML cube at
# 8 M cells, the PEC box at 17 M and 3 M cells, and the SMA board (needs RFSIM_PATH; skipped without). About 25 minutes.
# The record results/tiled_sweep_cg32_2026-11-11.txt was made with a first version without the fused run at T3.
if (( $# < 3 )); then echo "usage: time.zsh NEW REF OUT_DIR [T1 T2 T3]" >&2; exit 1; fi
S=$1; REF=$2; O=${3:A}; T1=${4:-4}; T2=${5:-8}; T3=${6:-10}; R=${ROUNDS:-3}
mkdir -p $O; cd ${0:A:h:h:h}
print "start $(date '+%F %T')" | tee $O/when.txt
H="OPENEMS_TBLOCK=auto;OPENEMS_TBLOCK_HOOKS=0"
ROWS=("patch 5 1000 OPENEMS_TBLOCK=4 $H" "notch 3 1500 OPENEMS_TBLOCK=8;OPENEMS_TBLOCK_W=17 $H" "cube 2 600 OPENEMS_TBLOCK=4 $H"
      "lbox 2 400 OPENEMS_TBLOCK=3 OPENEMS_TBLOCK=2" "lbox 1 2000 OPENEMS_TBLOCK=8;OPENEMS_TBLOCK_W=33 OPENEMS_TBLOCK=4")
[[ -n "$RFSIM_PATH" ]] && ROWS+=("ksma 1 6000 OPENEMS_TBLOCK=8;OPENEMS_TBLOCK_W=17 OPENEMS_TBLOCK=8;OPENEMS_TBLOCK_W=65")
for row in $ROWS; do
  set -- ${=row}
  python3 bench/abtest.py $1 --scale $2 --nrts $3 --rounds $R --quiet ${QUIET:-120} --quiet-max ${QUIET_MAX:-90} --run-redo 1 \
    --configs $REF@multithreaded:$T1 $REF@multithreaded:$T2 $REF@multithreaded:$T3 \
              "$S@multithreaded:$T1#OPENEMS_TBLOCK=auto" "$S@multithreaded:$T2#OPENEMS_TBLOCK=auto" "$S@multithreaded:$T3#OPENEMS_TBLOCK=auto" \
              "$S@multithreaded:$T2#OPENEMS_TBLOCK=auto;OPENEMS_BALANCE=0" "$S@multithreaded:$T1#$4" "$S@multithreaded:$T1#$5" \
    --out $O/${1}_s$2.txt > $O/${1}_s$2.log 2>&1
  print "$1 s$2 $(date +%T)"; grep -E "^c[0-9]" $O/${1}_s$2.log | cut -c1-175
done
print "end $(date '+%F %T')" | tee -a $O/when.txt
