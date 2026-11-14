#!/bin/zsh
# Slot T1 (M5 Pro, 2026-11-12): the automatic thread count of cg33a against cg31.
# cg33a = fork 0ef186b + the tuner starting at every core outside the efficiency cluster (15 here) and stepping down by 2 while
# that is faster; OPENEMS_TUNE_START=p = the old rule (start at hw.perflevel0 = 5, up in steps of 2), a control that must run
# like cg31:0. cg31:15 = the best fixed count of the m5pro set. Run lengths as in the m5pro speed table and the toolkit's e2e
# runs (GCPW 34300 and SMA 50320 steps = the probe-end stop steps of the toolkit defaults).
# Needs M5PRO_OUT and RFSIM_PATH (common.zsh) and the snapshots cg31 and cg33a in the snapshot folder.
source ${0:A:h}/common.zsh
print "tune33 start $(date '+%F %T')"; zsh $M5PRO_DIR/wait_quiet.zsh 80 6 ${GATE:-300} || print "not quiet at the start: running anyway, read the others column of every line"
for row in "kgcpw 1 34300" "notch 3 2000" "patch 5 1200" "ksma 1 50320"; do
  set -- ${=row}
  ab tune33_${1}_s$2 $1 $2 $3 4 cg31@multithreaded:15 cg31@multithreaded:0 cg33a@multithreaded:0 "cg33a@multithreaded:0#OPENEMS_TUNE_START=p"
done
print "tune33 end $(date '+%F %T')"
