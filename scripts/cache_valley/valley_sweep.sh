#!/bin/zsh
# valley_sweep.sh LIB_DIR: the allocation-placement valley (see placement.sh). box.py on one thread for 2000 steps,
# nz=20, nx=ny from 60 to 170, with the allocator stagger and without it (OPENEMS_NO_STAGGER=1), on the libraries in
# LIB_DIR (libopenEMS.0.dylib, libCSXCAD.0.dylib, libnf2ff.0.dylib of a fork build: the stagger came with patch 0003).
# Writes valley.txt and the run folders run_a, run_b next to this script. The published sweep
# (results/cache_valley_2026-11-01.txt) ran on the installed cg16 build (patches 0001-0004); on a stock folder both
# columns are stock (results/cache_valley_stock_2026-11-03.txt). A speed measurement: run it on a quiet machine.
# The script sets DYLD_LIBRARY_PATH itself for each python3 call (a DYLD_* variable set by the caller would not reach
# it: macOS drops DYLD_* when it starts /bin/zsh). Use a python3 that is not a macOS system binary.
if (( $# != 1 )); then
  echo "usage: valley_sweep.sh LIB_DIR   (a folder with libopenEMS.0.dylib, libCSXCAD.0.dylib, libnf2ff.0.dylib)" >&2
  exit 1
fi
LIB=${1:A}
for l in libopenEMS libCSXCAD libnf2ff; do
  if [[ ! -f $LIB/$l.0.dylib ]]; then
    echo "valley_sweep.sh: $LIB lacks $l.0.dylib (dyld would load the installed library instead)" >&2
    exit 1
  fi
done
cd "${0:A:h}"
(caffeinate -i -w $$ &)
BOX=./box.py
speed() { grep -oE "Speed: *[0-9.]+ MCells" | tail -1 | grep -oE "[0-9.]+"; }
echo "# nx ny nz cells MCs_stagger MCs_nostagger" > valley.txt
for n in 60 70 80 90 100 110 120 130 140 150 160 170; do
  c=$((n*n*20))
  a=$(DYLD_LIBRARY_PATH=$LIB python3 -B $BOX $n $n 20 2000 1 run_a 2>&1 | speed)
  b=$(DYLD_LIBRARY_PATH=$LIB OPENEMS_NO_STAGGER=1 python3 -B $BOX $n $n 20 2000 1 run_b 2>&1 | speed)
  echo "$n $n 20 $c $a $b" | tee -a valley.txt
done
echo DONE
