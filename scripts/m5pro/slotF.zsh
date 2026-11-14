#!/bin/zsh
# Slot F (M5 Pro, measured, about 60-75 min; start only from the night block's flag). Four parts, every line records the
# others' CPU; snapshots stock, cg31 (installed) and cg33d.
#  a. the stock baseline at 1, 2, 3, 4, 5, 10 and 15 threads on the six models (the 2026-11-12 table had only 5 and 10),
#     with cg31 at 15 threads as the link to that table; half the steps of stage C (fixed thread counts: no tuner)
#  b. GCPW board: cg33d packed sheets on / off against cg31, 15 threads
#  c. upstream bench.py WITH a source on the mesh (BENCH_ODD_LINES=1: 101 / 201 lines): master's cpu engine against the
#     fork cg33d, interleaved, ideal / pml / dispersive, S and M, 5 / 10 / 15 threads; then the same two binaries on
#     upstream's own even meshes (no source, all fields zero) for dispersive and ideal at M, 15 threads, as the control
#  d. tiled sweep probe, no new code: cg33d on dispersive and ideal at M (201 lines), fused against OPENEMS_TBLOCK
# Needs M5PRO_OUT, RFSIM_PATH (common.zsh), MASTER_DIR (the master build folder of master/build.zsh) and the snapshots
# stock, cg31 and cg33d. Output: $M5PRO_OUT/slotF/ (load.log, *_bench.out, *_result.json) and the tables of part a and b.
source ${0:A:h}/common.zsh
M=${MASTER_DIR:?set MASTER_DIR to the master build folder}; MH=$M5PRO_DIR/master; W=$O/slotF; mkdir -p $W
export MASTER_DIR
print "slot F start $(date '+%F %T'); $(uptime)"
zsh $M5PRO_DIR/wait_quiet.zsh 300 3 ${GATE:-300} || print "others above 3 cores at the start: running anyway, read the others column"
# Load of the others: the CPU of every process that is not a descendant of this script. (The first version excluded
# processes by name, 'openEMS|bench|abtest', and so counted the python children of abtest.py as others in parts a and b: its
# slot figure "median 68 %, p90 421 %" was not the others' load. The tree filter below leaves the benchmark's own
# processes out, the sampler and its ps included.)
others() {
  ps -A -o pid=,ppid=,%cpu= | awk -v root=$$ '
    { pid[NR]=$1; par[$1]=$2; cpu[$1]=$3; n=NR }
    END { for (i=1; i<=n; i++) { a=pid[i]; own=0; g=0
            while (a>1 && g<64) { if (a==root) { own=1; break }; a=par[a]; g++ }
            if (!own) s+=cpu[pid[i]] }
          printf "%.0f", s }'
}
( while true; do print "$(date +%T) others $(others) %"; sleep 5; done ) > $W/load.log 2>&1 &
lp=$!
# a
for row in "patch 1 5000" "patch 5 600" "notch 1 8000" "notch 3 1000" "kgcpw 1 7500" "ksma 1 3000"; do
  set -- ${=row}
  ab slotF_stock_${1}_s$2 $1 $2 $3 3 stock@multithreaded:1 stock@multithreaded:2 stock@multithreaded:3 stock@multithreaded:4 \
     stock@multithreaded:5 stock@multithreaded:10 stock@multithreaded:15 cg31@multithreaded:15
done
print "part a end $(date +%T)"
# b
ab slotF_gcpw_packed kgcpw 1 34300 4 cg31@multithreaded:15 cg33d@multithreaded:15 "cg33d@multithreaded:15#OPENEMS_ADE_PACKED=0"
print "part b end $(date +%T)"
# c
export FORK_SNAP=cg33d
BENCH_ODD_LINES=1 python3 $MH/bench_launch.py run --openems $M/prefix/bin/openEMS --label master --openems $MH/fork_snap_cpu.zsh --label cg33d \
  --engine cpu --cases ideal,pml,dispersive --threads 5,10,15 --size S,M --repeat 3 --workdir $W/src_runs -o $W/src_result.json > $W/src_bench.out 2>&1
print "part c (source on the mesh) bench.py exit $? $(date +%T)"; tail -30 $W/src_bench.out | cut -c1-170
python3 $MH/bench_launch.py run --openems $M/prefix/bin/openEMS --label master --openems $MH/fork_snap_cpu.zsh --label cg33d \
  --engine cpu --cases ideal,dispersive --threads 15 --size M --repeat 3 --workdir $W/nosrc_runs -o $W/nosrc_result.json > $W/nosrc_bench.out 2>&1
print "part c (upstream's meshes, no source) bench.py exit $? $(date +%T)"; tail -12 $W/nosrc_bench.out | cut -c1-170
# d
BENCH_ODD_LINES=1 python3 $MH/bench_launch.py run --openems $MH/fork_snap_cpu.zsh --label cg33d --variant fused: \
  --variant tbauto:OPENEMS_TBLOCK=auto --variant tb4:OPENEMS_TBLOCK=4 --variant tbw31:OPENEMS_TBLOCK=auto,OPENEMS_TBLOCK_W=31 \
  --engine cpu --cases ideal,dispersive --threads 5,10,15 --size M --repeat 3 --workdir $W/tb_runs -o $W/tb_result.json > $W/tb_bench.out 2>&1
print "part d bench.py exit $? $(date +%T)"; tail -30 $W/tb_bench.out | cut -c1-170
kill $lp 2>/dev/null
# Was there a source? The largest probe value of every run folder, one line per folder (the first version grouped a
# case's warm-up folder with its runs under the top folder's name, so a run without a source could hide behind one with).
python3 - $W <<'PY'
import os, sys
for sub in ('src_runs', 'nosrc_runs', 'tb_runs'):
    base = os.path.join(sys.argv[1], sub)
    peak = {}
    for root, _, fs in os.walk(base):
        for f in fs:
            if f in ('et', 'ht'):
                m = 0.0
                for l in open(os.path.join(root, f), errors='replace'):
                    if l.startswith('%') or not l.strip(): continue
                    try: m = max([m] + [abs(float(x)) for x in l.split()[1:]])
                    except ValueError: pass
                key = os.path.relpath(root, base)
                peak[key] = max(peak.get(key, 0.0), m)
    print(sub, 'probe peaks, one line per run folder:' if peak else ': no probe files found')
    for k in sorted(peak): print('  %s  %.3g' % (k, peak[k]))
PY
awk '{print $3}' $W/load.log | sort -n | awk '{a[NR]=$1} END{if(NR) printf "others during slot F: median %s %%, p90 %s %%, max %s %% of one core (%d samples)\n", a[int((NR+1)/2)], a[int(NR*0.9)+0], a[NR], NR}'
print "slot F end $(date '+%F %T')"
