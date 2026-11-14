#!/bin/zsh
# Slot T2 (M5 Pro, 2026-11-12): upstream master's cpu engine (openEMS 1d710c2, CSXCAD fdff4b5, built by master/build.zsh into
# $MASTER_DIR/prefix) against the fork's CPU engine (the installed cg31, fused sweep), INTERLEAVED run for run by upstream's
# own benchmark/bench.py: --openems master (engine cpu) and --openems master/fork_as_cpu.zsh (the installed fork binary with
# --engine=cpu mapped to multithreaded). Six cases, sizes S (~1 M) and M (~8 M), 5/10/15 threads, 3 runs each.
# OPENEMS_CPU_TRIAL=0 for master's cpu engine is bench.py's own default (steady state). Others' CPU sampled every 5 s.
# Part 2: the packed dispersive hooks, cg31 against cg33c, interleaved, fixed thread counts (the tuner is not involved).
# NOTE (2026-11-13): upstream's meshes of 100 and 200 lines have no source, so ideal, pml and dispersive ran on zero
# fields in this slot; slotF.zsh part c repeats the comparison with BENCH_ODD_LINES=1 (a source on the mesh).
# Needs M5PRO_OUT, MASTER_DIR (the master build folder, with src/ and prefix/) and the snapshot cg33c.
O=${M5PRO_OUT:?set M5PRO_OUT to an output folder}; M=${MASTER_DIR:?set MASTER_DIR to the master build folder}
MH=${0:A:h}/master; PFX=${OPENEMS_PREFIX:-$HOME/opt/openEMS}
W=$O/master33; mkdir -p $W $O/logs
print "master33 start $(date '+%F %T')"
zsh ${0:A:h}/wait_quiet.zsh 80 6 ${GATE:-300} || print "not quiet at the start: running anyway, see load.log"
( while true; do print "$(date +%T) others $(ps -A -o %cpu=,comm= | grep -v -E 'openEMS|bench' | awk '{s+=$1} END{printf "%.0f", s}') %"; sleep 5; done ) > $W/load.log 2>&1 &
lp=$!
export MASTER_DIR
python3 $MH/bench_launch.py run --openems $M/prefix/bin/openEMS --label master --openems $MH/fork_as_cpu.zsh --label fork \
  --engine cpu --threads 5,10,15 --size S,M --repeat 3 --workdir $W/runs -o $W/result.json > $W/bench.out 2>&1
rc=$?
print "master33 bench.py exit $rc (1 = a probe MISMATCH above 1e-4 or an error; read bench.out)"
tail -45 $W/bench.out | cut -c1-160
print "ade A/B start $(date +%T)"
export FORK_SNAP=cg33c   # only the second binary below goes through fork_snap_cpu.zsh, which reads it
python3 $MH/bench_launch.py run --openems $PFX/bin/openEMS --label cg31 --openems $MH/fork_snap_cpu.zsh --label cg33c \
  --engine multithreaded --cases dispersive,antenna --threads 5,15 --size S,M --repeat 3 --workdir $W/ade_runs -o $W/ade_result.json > $W/ade.out 2>&1
print "ade A/B bench.py exit $? (probes must say identical)"
kill $lp 2>/dev/null
tail -14 $W/ade.out | cut -c1-160
print "master33 end $(date '+%F %T')"
