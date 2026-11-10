#!/bin/zsh
# placement.sh LIB_DIR: what triggers the valley of valley_sweep.sh (added 2026-11-03), one thread throughout.
#  1. place.c: the distance at which the allocator puts two equal blocks of 1-8 MB.
#  2. ../kernel/kb_idx.cpp (KB_ONE=1, Apple clang) at 110 x 110 x 20, a valley size: the current array moved by
#     KB_PAD bytes away from its natural place, 0 to 64 KiB, three interleaved rounds. 'diff' is its distance
#     from the voltage array.
#  3. box.py at the two edges of the valley (nz = 20: nx = ny = 93 / 94 put each field array just below / above
#     2 MiB, 132 / 133 just below / above 4 MiB), with the allocator stagger and without it
#     (OPENEMS_NO_STAGGER=1), two rounds, on the libraries in LIB_DIR (a fork build; stock has no stagger).
# A speed measurement: run it on a quiet machine. The binaries and run folders go to ${TMPDIR:-/tmp}/emskit_placement.
# The script sets DYLD_LIBRARY_PATH itself for each python3 call (macOS drops DYLD_* when it starts /bin/zsh); use a
# python3 that is not a macOS system binary.
if (( $# != 1 )); then
  echo "usage: placement.sh LIB_DIR   (a folder with libopenEMS.0.dylib, libCSXCAD.0.dylib, libnf2ff.0.dylib)" >&2
  exit 1
fi
LIB=${1:A}
for l in libopenEMS libCSXCAD libnf2ff; do
  if [[ ! -f $LIB/$l.0.dylib ]]; then
    echo "placement.sh: $LIB lacks $l.0.dylib (dyld would load the installed library instead)" >&2
    exit 1
  fi
done
HERE=${0:A:h}
W=${TMPDIR:-/tmp}/emskit_placement
mkdir -p $W || exit 1
(caffeinate -i -w $$ &)
echo "# placement.sh $(date '+%Y-%m-%d %H:%M'), $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string)"
echo "# libraries: $LIB ($(strings $LIB/libopenEMS.0.dylib | grep -m1 -oE 'v0\.37\.0[-a-z0-9]*'))"

echo "## 1. place.c"
cc -O2 $HERE/place.c -o $W/place || exit 1
$W/place

echo "## 2. kb_idx 300 steps at 110 x 110 x 20, one thread: KB_PAD (bytes), stock and clean loops (MC/s), distance"
clang++ -std=c++17 -O3 -DNDEBUG $HERE/../kernel/kb_idx.cpp -o $W/kb_idx || exit 1
for r in 1 2 3; do
  for pad in 0 256 512 1024 2560 4096 8192 16384 32768 65536; do
    out=$(KB_ONE=1 KB_PAD=$pad $W/kb_idx 300 110 110 20)
    st=$(print -r -- $out | grep 'stock, 1 thread' | grep -oE '[0-9]+ MC/s' | grep -oE '[0-9]+')
    cl=$(print -r -- $out | grep 'clean, 1 thread' | grep -oE '[0-9]+ MC/s' | grep -oE '[0-9]+')
    di=$(print -r -- $out | grep -oE 'diff -?[0-9]+ KB')
    echo "round $r  KB_PAD $pad  stock $st  clean $cl  $di"
  done
done

echo "## 3. box.py 2000 steps, nz = 20, one thread: nx = ny, cells, bytes per field array, MC/s staggered / OPENEMS_NO_STAGGER=1"
speed() { grep -oE "Speed: *[0-9.]+ MCells" | tail -1 | grep -oE "[0-9.]+"; }
for r in 1 2; do
  for n in 90 92 93 94 96 130 132 133 134 136; do
    a=$(DYLD_LIBRARY_PATH=$LIB python3 -B $HERE/box.py $n $n 20 2000 1 $W/run_a 2>&1 | speed)
    b=$(DYLD_LIBRARY_PATH=$LIB OPENEMS_NO_STAGGER=1 python3 -B $HERE/box.py $n $n 20 2000 1 $W/run_b 2>&1 | speed)
    echo "round $r  n $n  cells $((n*n*20))  array $((240*n*n)) B  stagger $a  nostagger $b"
  done
done
echo DONE
