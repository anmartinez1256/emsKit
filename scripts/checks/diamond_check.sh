#!/bin/zsh
# diamond_check.sh SNAP_DIR: the bit-identity test of the diamond-blocked Metal engine (--engine=metal-diamond).
# Runs diamond_box.py (a box with a dielectric slab, soft E excitations, one of them delayed, a soft H excitation, and
# either an E excitation on the x-min Mur plane, so that face starts late, or lumped elements: parallel RLC, series
# RLC, series LC) on the multithreaded engine with OPENEMS_FTZ=1 and on the Metal engine for K = 1, 2, 3, 4, 8, an
# odd tile/threadgroup/batch setting and the tile tuner (the tilings change between command buffers), with PEC, Mur on
# all six faces, MUR/PEC/PEC/MUR/MUR/PMC, PML_8 on all six faces and
# PML_8/MUR/PEC/PML_8/MUR/PML_8 (Mur faces that cross the PML boxes, with the lumped elements), conducting sheets on
# the Mur box, a two-pole Debye block on the Mur box, and everything together with two Drude/Lorentz blocks (eps and mue
# ADEs, with and without the Lorentz pole) and the Debye block; compares the
# exported final fields (diamond_compare.py): they must be bit-identical.
# Apple's GPU flushes subnormals to zero, so the CPU reference runs with OPENEMS_FTZ=1 (BUILD.md, section 7).
# SNAP_DIR holds libopenEMS.0.dylib + libCSXCAD.0.dylib + libnf2ff.0.dylib of a fork build with ENABLE_METAL.
# The runs go to a temporary folder that is removed at the end. Exit status 0 when every comparison is identical.
set -e
if (( $# != 1 )); then
  echo "usage: diamond_check.sh SNAP_DIR   (folder with the three .0.dylib files of a fork build)" >&2
  exit 1
fi
SNAP=${1:A}
for l in libopenEMS libCSXCAD libnf2ff; do
  if [[ ! -f $SNAP/$l.0.dylib ]]; then
    echo "diamond_check.sh: $SNAP lacks $l.0.dylib (dyld would load the installed library instead)" >&2
    exit 1
  fi
done
cd "${0:A:h}"
W=$(mktemp -d "${TMPDIR:-/tmp}/diamond_check.XXXXXX")
trap 'rm -rf "$W"' EXIT
rc=0
cmpf() {   # cmpf REF OUT LABEL
  if python3 -B diamond_compare.py $1 $2 > $W/cmp.txt; then echo "  $3: IDENTICAL"; else rc=1; echo "  $3: DIFFERENT"; cat $W/cmp.txt; fi
}
for spec in "pec 41,37,30 400" "mur 41,37,30 400" "mixed 43,38,29 700 --hexc --delay --murexc" "mixed 43,38,29 1500 --hexc --delay --rlc" \
            "pml 41,37,30 400 --hexc --delay" "pmlmix 43,38,29 700 --hexc --delay --rlc" \
            "mur 41,37,30 500 --sheet" "mur 41,37,30 300 --debye" \
            "pmlmix 43,38,29 700 --hexc --delay --rlc --drude --sheet --debye"; do
  set -- ${=spec}; bc=$1; n=$2; ts=$3; shift 3
  echo "== $bc, $n lines, $ts timesteps $*"
  DYLD_LIBRARY_PATH=$SNAP OPENEMS_FTZ=1 python3 -B diamond_box.py $W/s $W/cpu_$bc --n $n --nrts $ts --bc $bc "$@" \
    --engine multithreaded --threads 4 > $W/log 2>&1 || { echo "  CPU run failed:"; tail -5 $W/log; exit 1; }
  for K in 1 2 3 4 8; do
    DYLD_LIBRARY_PATH=$SNAP OPENEMS_DIAMOND_K=$K python3 -B diamond_box.py $W/s $W/gpu --n $n --nrts $ts --bc $bc "$@" \
      --engine metal-diamond > $W/log 2>&1 || { echo "  Metal run failed:"; tail -5 $W/log; exit 1; }
    if ! grep -q "Engine_Metal_Diamond: .*K=" $W/log; then echo "  K=$K: the GPU path did not run"; tail -5 $W/log; rc=1; continue; fi
    cmpf $W/cpu_$bc $W/gpu "K=$K"
  done
  DYLD_LIBRARY_PATH=$SNAP OPENEMS_DIAMOND_TILE=7,0 OPENEMS_DIAMOND_TG=96 OPENEMS_DIAMOND_BATCH=3 python3 -B diamond_box.py \
    $W/s $W/gpu --n $n --nrts $ts --bc $bc "$@" --engine metal-diamond > $W/log 2>&1 || { echo "  Metal run failed"; exit 1; }
  cmpf $W/cpu_$bc $W/gpu "K=4, tile 7,0, 96 threads, batch 3"
  # the tuner: four tilings in turn per command buffer, then the fastest (batch 8: 4-step command buffers while tuning,
  # so it finishes within these runs) or, with the default batch, the tilings in turn for most of the run
  DYLD_LIBRARY_PATH=$SNAP OPENEMS_DIAMOND_BATCH=8 python3 -B diamond_box.py $W/s $W/gpu --n $n --nrts $ts --bc $bc "$@" \
    --engine metal-diamond > $W/log 2>&1 || { echo "  Metal run failed"; exit 1; }
  if ! grep -q "timesteps of tuning" $W/log; then echo "  tuned, batch 8: the tuning did not finish"; tail -5 $W/log; rc=1; fi
  cmpf $W/cpu_$bc $W/gpu "tuned, batch 8 ($(grep -o 'K=[0-9]* tiles [0-9,]* after [0-9]*' $W/log | head -1) steps)"
  DYLD_LIBRARY_PATH=$SNAP python3 -B diamond_box.py $W/s $W/gpu --n $n --nrts $ts --bc $bc "$@" \
    --engine metal-diamond > $W/log 2>&1 || { echo "  Metal run failed"; exit 1; }
  cmpf $W/cpu_$bc $W/gpu "tuning, default batch"
done
if (( rc )); then echo "FAIL: at least one comparison differs"; else echo "PASS: every comparison is identical"; fi
exit $rc
