#!/bin/zsh
# check.zsh NEW REF [T1 T2 T3 T4]: the tiled sweep of the multithreaded engine (OPENEMS_TBLOCK, patch 0040) against the
# fused sweep; results must be identical. NEW and REF are snapshot names for bench/bench.py: folders in
# $OPENEMS_BENCH_SNAPS (default ~/opt/openEMS-dev/snap) with libopenEMS.0.dylib, libCSXCAD.0.dylib and libnf2ff.0.dylib of a
# fork build. REF runs the fused sweep (it may be NEW itself), NEW the tiled one. T1..T4: thread counts (default 4 8 10 3;
# "2 2 2 1" fits two cores). From the repository root, python3 with the openEMS module.
#   1. probes of the harness models patch, notch, lbox, cube (and kgcpw, ksma with RFSIM_PATH): REF fused against NEW at
#      depths 3 to 7 and auto, with OPENEMS_BALANCE=0, OPENEMS_TBLOCK_HOOKS=0 and a set tile width among the settings
#   2. the closed cylinder of scripts/cylinder_closed: raw fields, tiled against untiled
#   3. ss_box.py, a sinusoidal run that stops by the steady-state criterion: same stop step, probes and raw fields
#   4. scripts/checks/debye_check.sh with OPENEMS_TBLOCK set
# Verdicts only: the speeds in the tables count for nothing unless the machine is quiet (time.zsh is for that).
# The counts of 2026-11-11 in results/tiled_sweep_cg32_2026-11-11.txt (30 of 30, 36 of 36, 42 of 42) are from earlier forms
# of this script with five to seven tiled settings a model; this form runs eight (48 of 48 with the two boards).
# Tables go to OUT (default: a temporary folder, removed at the end with the run folders). Exit status 0 = all identical.
if (( $# < 2 )); then echo "usage: check.zsh NEW REF [T1 T2 T3 T4]" >&2; exit 1; fi
NEW=$1; REF=$2; shift 2; T=(${@:-4 8 10 3})
if (( ${#T} != 4 )); then echo "check.zsh: four thread counts, or none" >&2; exit 1; fi
ROOT=${0:A:h:h:h}; SNAPS=${OPENEMS_BENCH_SNAPS:-$HOME/opt/openEMS-dev/snap}; SN=$SNAPS/$NEW
for l in libopenEMS libCSXCAD libnf2ff; do
  [[ -f $SN/$l.0.dylib ]] || { echo "check.zsh: $SN lacks $l.0.dylib" >&2; exit 1; }
done
TMP=$(mktemp -d /tmp/tiled_check.XXXXXX); O=${OUT:-$TMP/out}; mkdir -p $O
export OPENEMS_BENCH_RUNS=$TMP/runs; mkdir -p $OPENEMS_BENCH_RUNS
bad=0; cd $ROOT
CFG=($REF@multithreaded:$T[1] "$NEW@multithreaded:$T[1]#OPENEMS_TBLOCK=4" "$NEW@multithreaded:$T[2]#OPENEMS_TBLOCK=7"
     "$NEW@multithreaded:$T[3]#OPENEMS_TBLOCK=5;OPENEMS_TBLOCK_W=23" "$NEW@multithreaded:$T[4]#OPENEMS_TBLOCK=6"
     "$NEW@multithreaded:$T[2]#OPENEMS_TBLOCK=4;OPENEMS_BALANCE=0" "$NEW@multithreaded:$T[3]#OPENEMS_TBLOCK=3;OPENEMS_TBLOCK_HOOKS=0"
     "$NEW@multithreaded:$T[1]#OPENEMS_TBLOCK=auto" "$NEW@multithreaded:$T[3]#OPENEMS_TBLOCK=auto")
ROWS=("patch 1 3000" "notch 1 3000" "lbox 1 400" "cube 1 400")
if [[ -n "$RFSIM_PATH" ]]; then ROWS+=("kgcpw 1 3000" "ksma 1 800"); else print "RFSIM_PATH is not set: kgcpw and ksma skipped"; fi
for row in $ROWS; do
  set -- ${=row}
  python3 bench/abtest.py $1 --scale $2 --nrts $3 --rounds 1 --configs $CFG --out $O/${1}_s$2.txt > $O/${1}_s$2.log 2>&1
  n=$(grep -c '^c[0-9].* identical' $O/${1}_s$2.log); want=$(( ${#CFG} - 1 ))
  print "$1 s$2: $n of $want identical"; (( n == want )) || bad=1
done
# 2. the closed cylinder, raw fields
W=$TMP/cyl; mkdir -p $W/f0 $W/f1 $W/f2; C=$ROOT/scripts/cylinder_closed/cyl_closed.py
OPENEMS_EXPORT_FIELDS=$W/f0 DYLD_LIBRARY_PATH=$SN python3 $C $W/s0 1500 2 > $W/l0 2>&1
OPENEMS_TBLOCK=4 OPENEMS_EXPORT_FIELDS=$W/f1 DYLD_LIBRARY_PATH=$SN python3 $C $W/s1 1500 $T[2] > $W/l1 2>&1
OPENEMS_TBLOCK=7 OPENEMS_EXPORT_FIELDS=$W/f2 DYLD_LIBRARY_PATH=$SN python3 $C $W/s2 1500 $T[3] > $W/l2 2>&1
for k in 1 2; do
  if [[ -s $W/f0/volt.f32 ]] && cmp -s $W/f0/volt.f32 $W/f$k/volt.f32 && cmp -s $W/f0/curr.f32 $W/f$k/curr.f32; then
    print "cylinder raw fields, tiled run $k: identical"
  else print "cylinder raw fields, tiled run $k: DIFFER"; bad=1; fi
done
grep -q "tiled sweep, " $W/l1 || { print "cylinder: the tiled sweep was not active in run 1"; bad=1; }
# 3. steady-state detection
W=$TMP/ss; mkdir -p $W; B=$ROOT/scripts/tiled_sweep/ss_box.py; KS=(4 8 19 5)
ss() {  # name, snapshot folder, threads, environment assignments
  local n=$1 lib=$2 t=$3; shift 3; mkdir -p $W/f_$n
  env "$@" OPENEMS_EXPORT_FIELDS=$W/f_$n DYLD_LIBRARY_PATH=$lib python3 $B $W/s_$n 30000 $t 6 1e-2 > $W/l_$n 2>&1
}
ss ref $SNAPS/$REF 2 X=1; ss fused $SN 2 X=1
for i in 1 2 3 4; do ss tiled$i $SN $T[$i] OPENEMS_TBLOCK=$KS[$i]; done
python3 - $W <<'PY' || bad=1
import sys, os, numpy as np
w = sys.argv[1]; bad = 0
def load(n):
    pr = [np.loadtxt(os.path.join(w, 's_'+n, 'port_ut%d' % k), comments='%') for k in (1, 2, 3, 4)]
    fl = [np.fromfile(os.path.join(w, 'f_'+n, f), dtype=np.uint32) for f in ('volt.f32', 'curr.f32')]
    return pr, fl
rp, rf = load('ref')
print('steady state, reference: %d samples, field peak %.3e' % (len(rp[0]), np.abs(rf[0].view(np.float32)).max()))
for n in ('fused', 'tiled1', 'tiled2', 'tiled3', 'tiled4'):
    p, f = load(n)
    same_len = all(len(a) == len(b) for a, b in zip(p, rp))
    same_pr = same_len and all(np.array_equal(a, b) for a, b in zip(p, rp))
    same_fl = all(a.size == b.size and np.array_equal(a, b) for a, b in zip(f, rf))
    bad += not (same_pr and same_fl)
    print('  %-7s stop step %s, probes %s, raw fields %s' % (n, 'same' if same_len else 'DIFFERENT', 'identical' if same_pr else 'DIFFER',
          'identical' if same_fl else 'DIFFER'))
sys.exit(1 if bad or len(rp[0]) < 100 or not np.abs(rf[0].view(np.float32)).max() > 0 else 0)
PY
# 4. Debye
if OPENEMS_TBLOCK=4 zsh $ROOT/scripts/checks/debye_check.sh $SN > $TMP/debye.log 2>&1; then print "debye_check with OPENEMS_TBLOCK=4: pass"
else print "debye_check with OPENEMS_TBLOCK=4: FAIL"; tail -3 $TMP/debye.log; bad=1; fi
if [[ -d $TMP && $TMP == /tmp/tiled_check.* ]]; then
  if [[ -n "$OUT" ]]; then rm -r $TMP/runs $TMP/cyl $TMP/ss; else rm -r $TMP; fi
fi
(( bad )) && { print "FAIL: at least one comparison differs"; exit 1; }
print "PASS: the tiled sweep equals the fused sweep in every comparison"
