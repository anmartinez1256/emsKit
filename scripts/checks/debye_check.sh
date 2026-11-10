#!/bin/zsh
# debye_check.sh SNAP_DIR [REF_SNAP_DIR]: the Debye-material regression test (review of 2026-11-02).
# Runs scripts/cache_valley/box.py with a two-pole Debye block (DEBYE=1) on the basic, sse-compressed and
# multithreaded engines of the library in SNAP_DIR (libopenEMS.0.dylib + libCSXCAD.0.dylib + libnf2ff.0.dylib)
# and compares the exported final fields: they must be bit-identical. Before the fix the multithreaded engine
# skipped the Debye extension's Pre/Post voltage hooks (it inherited Engine_Ext_Dispersive's hook declaration) and
# differed from the single-threaded engines by 37 % of the peak field (60x60x20 box, 600 steps, 4 threads).
# With REF_SNAP_DIR the sse-compressed fields of both libraries are compared too (the single engine must not change).
# Both folders must hold a build of this fork: stock openEMS does not write OPENEMS_EXPORT_FIELDS.
# THREADS=N sets the multithreaded engine's thread count (default 4). The runs go to a temporary folder that is
# removed at the end. Exit status 0 when every comparison is identical, 1 otherwise.
# The script sets DYLD_LIBRARY_PATH itself for each python3 call (a DYLD_* variable set by the caller would not
# reach it: macOS drops DYLD_* when it starts /bin/zsh).
set -e
if (( $# < 1 || $# > 2 )); then
  echo "usage: debye_check.sh SNAP_DIR [REF_SNAP_DIR]   (folders with the three .0.dylib files of a fork build)" >&2
  exit 1
fi
SNAP=${1:A}; REF=""
if [[ -n "$2" ]]; then REF=${2:A}; fi
for d in $SNAP $REF; do
  for l in libopenEMS libCSXCAD libnf2ff; do
    if [[ ! -f $d/$l.0.dylib ]]; then
      echo "debye_check.sh: $d lacks $l.0.dylib (dyld would load the installed library instead)" >&2
      exit 1
    fi
  done
done
cd "${0:A:h}"
BOX=../cache_valley/box.py
THREADS=${THREADS:-4}
W=$(mktemp -d "${TMPDIR:-/tmp}/debye_check.XXXXXX")
trap 'rm -rf "$W"' EXIT
run() {   # run LIB_DIR ENGINE TAG
  mkdir -p $W/$3
  DYLD_LIBRARY_PATH=$1 OPENEMS_EXPORT_FIELDS=$W/$3 DEBYE=1 ENG=$2 python3 -B $BOX 60 60 20 600 $THREADS $W/run_$3 2>&1 \
    | grep -E 'Speed|Error' | tail -1
  if [[ ! -s $W/$3/volt.f32 || ! -s $W/$3/curr.f32 ]]; then
    echo "debye_check.sh: no exported fields from $1 ($2): the run failed, or the library is not a build of this fork" >&2
    exit 1
  fi
}
fieldcmp() {   # fieldcmp TAG_A TAG_B: exit status 1 when any value differs
python3 -B - "$W/$1" "$W/$2" <<'EOF'
import sys, os, numpy as np
a, b = sys.argv[1:3]; bad = 0
for f in ("volt.f32", "curr.f32"):
    x = np.fromfile(os.path.join(a, f), np.float32); y = np.fromfile(os.path.join(b, f), np.float32)
    if x.size != y.size:
        print(f"  {f}: {x.size} vs {y.size} values"); bad += 1; continue
    n = int((x != y).sum()); bad += n
    print(f"  {f}: max|x| {np.abs(x).max():.3e}  max|diff| {np.abs(x-y).max():.3e}  differing values {n}/{x.size}")
print("  IDENTICAL" if bad == 0 else "  DIFFERENT")
sys.exit(1 if bad else 0)
EOF
}
rc=0
echo "== $SNAP: basic / sse-compressed / multithreaded($THREADS)"
run $SNAP basic b; run $SNAP sse-compressed s; run $SNAP multithreaded m
echo "basic vs sse-compressed:"; fieldcmp b s || rc=1
echo "sse-compressed vs multithreaded:"; fieldcmp s m || rc=1
if [[ -n "$REF" ]]; then
  echo "== reference $REF: sse-compressed"; run $REF sse-compressed rs
  echo "sse-compressed, SNAP vs REF:"; fieldcmp s rs || rc=1
fi
if (( rc )); then echo "FAIL: at least one comparison differs"; else echo "PASS: every comparison is identical"; fi
exit $rc
