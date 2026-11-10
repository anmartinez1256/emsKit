#!/bin/zsh
# Run the six benchmark models on other openEMS builds next to emsKit, and compare every run with stock:
#   run_others.sh OUT RUNS
# OUT: folder for the tables (bench.py --out); RUNS: folder for the run directories, one subfolder per build.
# Builds (defaults as built on 2026-11-04, ~/opt/src/emskit-compare):
#   emsKit:     python3 on PATH with the install's modules; stock@multithreaded:T is the reference (as in
#               bench/check.sh), then cg18@multithreaded:4 and cg18@fastest (snapshots, bench.py's LIB@)
#   MASTER_PY:  upstream master (default ~/opt/openEMS-master/venv/bin/python3): multithreaded:4, then gpu (its
#               Metal backend)
#   LUIKORE_PY: openEMS pull request #228 (default ~/opt/openEMS-luikore/venv/bin/python3): multithreaded:4, then
#               metal:4 (the diamond path) in one call and metal:4 with OPENEMS_METAL_FUSED_PIPELINE=0 (the legacy
#               two-dispatch path) in another, so an abort of one does not stop the other
# NOMUR=1 runs the models with every MUR boundary replaced by PEC (OPENEMS_BENCH_BC; PML and PEC faces stay), the
# variant that luikore's diamond path can start (it refuses the Mur extension), and leaves out kgcpw (its
# conducting sheets are refused too); tables and comparisons get the suffix -nomur.
# ONLY="name ..." runs only those models (names as in MODELS below, e.g. to resume a stopped run).
# bench.py compares each GPU config with its own build's CPU engine ('tolerant'); xcompare.py then compares every
# run with the stock run. kgcpw and ksma need RFSIM_PATH. A failed bench.py call is reported and the script goes on.
cd "${0:A:h}"
if (( $# != 2 )); then
  echo "usage: run_others.sh OUT RUNS"
  exit 1
fi
OUT=${1:A}; RUNS=${2:A}
MASTER_PY=${MASTER_PY:-$HOME/opt/openEMS-master/venv/bin/python3}
LUIKORE_PY=${LUIKORE_PY:-$HOME/opt/openEMS-luikore/venv/bin/python3}
BENCH=../../bench/bench.py
B=(--repeat 2 --quiet ${QUIET:-100} --quiet-max ${QUIET_MAX:-90} --out $OUT)
SUF=${NOMUR:+-nomur}
mkdir -p $OUT $RUNS
# name | bench.py model arguments | stock reference threads (as in check.sh) | boundaries with MUR -> PEC (NOMUR=1)
MODELS=(
  "patch_s5_n1200|patch --scale 5 --nrts 1200|8|PEC;PEC;PEC;PEC;PEC;PEC"
  "notch_s3_n2000|notch --scale 3 --nrts 2000|8|PML_8;PML_8;PEC;PEC;PEC;PEC"
  "patch_s1_n10500|patch --nrts 10500|2|PEC;PEC;PEC;PEC;PEC;PEC"
  "notch_s1_n16000|notch --nrts 16000|4|PML_8;PML_8;PEC;PEC;PEC;PEC"
)
if [[ -n $RFSIM_PATH ]]; then
  MODELS+=("kgcpw_s1_n15000|kgcpw --nrts 15000|4|" "ksma_s1_n6000|ksma --nrts 6000|4|PEC;PEC;PEC;PEC;PEC;PML_8")
else
  echo "run_others.sh: RFSIM_PATH is not set: kgcpw and ksma skipped"
fi
call() {   # call TAG PYTHON SCRIPT ARGS...: one bench.py call, its exit status reported
  local tag=$1 py=$2; shift 2
  echo "=== $tag: $py ${*:t}"
  $py -W ignore "$@"
  echo "=== $tag: exit $?"
}
for m in $MODELS; do
  f=("${(@s:|:)m}"); name=$f[1]; args=(${=f[2]}); t=$f[3]
  [[ -n $ONLY && " $ONLY " != *" $name "* ]] && continue
  if [[ -n $NOMUR ]]; then
    if [[ -z $f[4] ]]; then
      echo "=== $name: skipped (NOMUR: no MUR-free variant)"
      continue
    fi
    export OPENEMS_BENCH_BC=$f[4]
    echo "=== $name: OPENEMS_BENCH_BC=$OPENEMS_BENCH_BC"
  fi
  call emskit python3 $BENCH $args $B --tag emskit$SUF --runs $RUNS/emskit \
    --configs stock@multithreaded:$t cg18@multithreaded:4 cg18@fastest
  call master $MASTER_PY $BENCH $args $B --tag master$SUF --runs $RUNS/master --configs multithreaded:4 gpu
  call luikore-metal $LUIKORE_PY bench_ext.py $args $B --tag luikore-metal$SUF --runs $RUNS/luikore-metal \
    --configs multithreaded:4 metal:4
  call luikore-legacy $LUIKORE_PY bench_ext.py $args $B --tag luikore-legacy$SUF --runs $RUNS/luikore-legacy \
    --configs multithreaded:4 'metal:4#OPENEMS_METAL_FUSED_PIPELINE=0'
  python3 -W ignore xcompare.py $args $RUNS/emskit/$name/stock_multithreaded_t$t/rep0 \
    $RUNS/emskit/$name/cg18_multithreaded_t4/rep0 $RUNS/emskit/$name/cg18_fastest/rep0 \
    $RUNS/master/$name/multithreaded_t4/rep0 $RUNS/master/$name/gpu/rep0 \
    $RUNS/luikore-metal/$name/multithreaded_t4/rep0 $RUNS/luikore-metal/$name/metal_t4/rep0 \
    $RUNS/luikore-legacy/$name/metal_t4_OPENEMS_METAL_FUSED_PIPELINE_0/rep0 | tee $OUT/${name}_xcompare$SUF.txt
done
