#!/bin/zsh
# Check snapshots against stock openEMS on the six benchmark models: check.sh TAG SNAP [SNAP2 ...]
# SNAP is a folder under ~/opt/openEMS-dev/snap (OPENEMS_BENCH_SNAPS) with libopenEMS.0.dylib, libCSXCAD.0.dylib and
# libnf2ff.0.dylib, or the path of such a folder; bench.py hands it to each run through DYLD_LIBRARY_PATH itself.
# The reference is the snapshot $STOCK (default "stock": stock v0.37.0, BUILD.md section 3). Every run's port probes
# and S-parameters must equal the reference's bit for bit. Tables: ../results/MODEL_sS_nN_TAG.txt.
# EXTRA="cfg ..." adds configs (e.g. EXTRA=mybuild@gpu; GPU and OPENEMS_FTZ configs are compared but not counted).
# LITE=1 runs the reduced set used for patch 0005 (4, 8 and automatic threads, one run each, no quiet wait).
# QUIET_MAX=s gives up the wait for a quiet Mac after s seconds per run (default 900; the line then says so): on a Mac
# shared with long jobs the full set would otherwise wait 15 minutes before each of its runs.
# Exit status: 0 = no differences (the last line says PARTIAL when RFSIM_PATH is unset and the two board models were
# skipped), 1 = a run failed or a snapshot folder is missing or incomplete, 2 = a difference or a missing file.
cd "${0:A:h}"
export OPENEMS_BENCH_RUNS=${OPENEMS_BENCH_RUNS:-/tmp/openems_bench_runs}
if (( $# < 2 )); then
  echo "usage: check.sh TAG SNAP [SNAP2 ...]"
  exit 1
fi
TAG=$1; shift
REF=${STOCK:-stock}
if [[ -n $LITE ]]; then
  T=(4 8); B=(--repeat 1 --tag $TAG)
else
  T=(1 4 8 10); B=(--repeat 2 --quiet 60 --quiet-max ${QUIET_MAX:-900} --tag $TAG)
fi
C=()
for s in "$@"; do
  for t in $T; do C+=($s@multithreaded:$t); done
  C+=($s@fastest)
done
C+=(${=EXTRA})
FAIL=()
run() {   # run LABEL REF_CONFIG MODEL ARGS...: one bench.py call; any exit status but 0 and 2 stops the check
  local label=$1 ref=$2; shift 2
  python3 -W ignore bench.py "$@" $B --configs $ref $C
  local rc=$?
  if (( rc == 2 )); then
    FAIL+=($label)
  elif (( rc != 0 )); then
    echo "check.sh $TAG: bench.py $label stopped with exit status $rc"
    exit 1
  fi
}
run patch_x5 $REF@multithreaded:8 patch --scale 5 --nrts 1200
run notch_x3 $REF@multithreaded:8 notch --scale 3 --nrts 2000
run patch $REF@multithreaded:2 patch --nrts 10500
run notch $REF@multithreaded:4 notch --nrts 16000
# the author's two boards: conducting sheet + Mur (kgcpw), coaxial port + z-only PML (ksma); they need the rfsim
# toolkit, which is not public (RFSIM_PATH = the folder that contains rfsim/)
if [[ -n $RFSIM_PATH ]]; then
  run kgcpw $REF@multithreaded:4 kgcpw --nrts 15000
  run ksma $REF@multithreaded:4 ksma --nrts 6000
fi
if (( ${#FAIL} )); then
  echo "check.sh $TAG: FAIL: $FAIL"
  exit 2
fi
if [[ -z $RFSIM_PATH ]]; then
  echo "check.sh $TAG: PARTIAL: no differences on 4 of 6 models (RFSIM_PATH is not set: kgcpw and ksma skipped)"
else
  echo "check.sh $TAG: ALL IDENTICAL (6 models)"
fi
