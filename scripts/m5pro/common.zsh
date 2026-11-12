# Shared settings of the M5 Pro stages (sourced by stageA.zsh to stageE.zsh; 2026-11-12, results/m5pro_*_2026-11-12.txt).
# M5PRO_OUT: the output folder (tables, logs); OPENEMS_BENCH_RUNS: the run folders (default $M5PRO_OUT/runs); RFSIM_PATH: the
# rfsim toolkit (models kgcpw and ksma, stage E). Snapshots stock, cg31 and cg32d as bench/bench.py takes them. The stages cd to
# the repository root.
M5PRO_DIR=${0:A:h}
O=${M5PRO_OUT:?set M5PRO_OUT to an output folder}
export RFSIM_PATH=${RFSIM_PATH:?set RFSIM_PATH to the rfsim toolkit}
export OPENEMS_BENCH_RUNS=${OPENEMS_BENCH_RUNS:-$O/runs}
mkdir -p $OPENEMS_BENCH_RUNS $O/logs
# Gate: wait up to 20 s for the other processes to use less than 3 cores (of 15) and redo a run once above that. On the
# machine of the record macOS's own indexing kept the others at 1 to 3.5 cores all night, so a stricter gate made nearly
# every run wait its full time and run twice. Every line still records the others' CPU and GPU: read that column.
Q=(--quiet 300 --quiet-max 20)
GATE=${GATE:-60}
load() { ps -A -o %cpu= | awk '{s+=$1} END{printf "%.0f", s}' }
ab() {  # name model scale steps rounds configs...
  local n=$1 m=$2 s=$3 ts=$4 r=$5; shift 5
  python3 bench/abtest.py $m --scale $s --nrts $ts --rounds $r $Q --run-redo 1 --configs "$@" --out $O/$n.txt > $O/logs/$n.log 2>&1
  local rc=$?
  print "== $n ($m s$s, $ts steps, $r rounds) done $(date +%T), exit $rc"
  grep -E "^c[0-9]" $O/logs/$n.log | sed "s/@multithreaded//; s/OPENEMS_//g" | cut -c1-170
}
cd ${M5PRO_DIR:h:h}
