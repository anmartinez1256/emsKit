# Shared settings of the Mac Studio stages (sourced by stageA.zsh to stageE.zsh and stageS.zsh; 2026-11-15,
# results/studio_speed_set_2026-11-15.txt). Machine of the record: Mac Studio, Apple M5 Max, 6 "Super" + 12 "Performance"
# cores, 36 GB, macOS 27.0.
# STUDIO_OUT: the output folder (tables, logs); OPENEMS_BENCH_RUNS: the run folders (default $STUDIO_OUT/runs); RFSIM_PATH:
# the rfsim toolkit (models kgcpw and ksma, stage E). Snapshots stock, cg31 and cg33 as bench/bench.py takes them. The
# stages cd to the repository root.
STUDIO_DIR=${0:A:h}
O=${STUDIO_OUT:?set STUDIO_OUT to an output folder}
export RFSIM_PATH=${RFSIM_PATH:?set RFSIM_PATH to the rfsim toolkit}
export OPENEMS_BENCH_RUNS=${OPENEMS_BENCH_RUNS:-$O/runs}
mkdir -p $OPENEMS_BENCH_RUNS $O/logs
# Gate: wait up to 20 s for the other processes to use less than 3 cores (of 18) and redo a run once above that. Every
# line records the others' CPU and GPU: read that column.
Q=(--quiet 300 --quiet-max 20)
GATE=${GATE:-60}        # seconds the start gate of a stage may wait
T1=6; T2=12; T3=18      # the Super cores, + six Performance cores, all cores
load() { ps -A -o %cpu= | awk '{s+=$1} END{printf "%.0f", s}' }
gate() { print "$1 start $(date '+%F %T'); $(uptime | sed 's/.*load/load/')"; zsh $STUDIO_DIR/wait_quiet.zsh 300 3 $GATE || print "others above 3 cores at the start: running anyway, read the others column of every line" }
ab() {  # name model scale steps rounds configs...
  local n=$1 m=$2 s=$3 ts=$4 r=$5; shift 5
  python3 bench/abtest.py $m --scale $s --nrts $ts --rounds $r $Q --run-redo 1 --configs "$@" --out $O/$n.txt > $O/logs/$n.log 2>&1
  local rc=$?
  print "== $n ($m s$s, $ts steps, $r rounds) done $(date +%T), exit $rc"
  grep -E "^c[0-9]" $O/logs/$n.log | sed "s/@multithreaded//; s/OPENEMS_//g" | cut -c1-170
}
cd ${STUDIO_DIR:h:h}
