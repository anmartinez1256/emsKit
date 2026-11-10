#!/bin/zsh
# Step 1: baseline of the stock openEMS v0.37.0 engines -> ../results/MODEL_sS_nN_step1.txt
# Runs the snapshot $STOCK (default "stock", the folder ~/opt/openEMS-dev/snap/stock with the three stock libraries,
# BUILD.md section 3), not whatever is installed; STOCK=NAME or STOCK=/path/to/folder picks another one.
cd "${0:A:h}"
export OPENEMS_BENCH_RUNS=${OPENEMS_BENCH_RUNS:-/tmp/openems_bench_runs}
L=${STOCK:-stock}
C=($L@basic $L@sse $L@sse-compressed $L@multithreaded:1 $L@multithreaded:2 $L@multithreaded:3 $L@multithreaded:4
   $L@multithreaded:5 $L@multithreaded:6 $L@multithreaded:8 $L@multithreaded:10 $L@fastest)
B=(--repeat 2 --quiet 60 --tag step1)
# bandwidth-bound sizes (~8 and ~5 MCells), fixed short runs
python3 -W ignore bench.py patch --scale 5 --nrts 1200 $B --configs $C $L@multithreaded:4+nodumps || exit $?
python3 -W ignore bench.py notch --scale 3 --nrts 2000 $B --configs $C || exit $?
# the tutorials at their own size (0.10 / 0.27 MCells), with fixed step counts (the tutorials themselves stop at their
# end criteria, -40 / -60 dB)
python3 -W ignore bench.py patch --nrts 10500 $B --configs $C $L@multithreaded:4+nodumps || exit $?
python3 -W ignore bench.py notch --nrts 16000 $B --configs $C || exit $?
