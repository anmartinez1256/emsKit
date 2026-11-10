#!/bin/zsh
# batch.sh LIB_DIR [REF]: the SMA mesh-floor sweep of 2026-11-02 (results/sma_mesh_sweep_2026-11-01.txt, second table):
# floors 0.02, 0.04 and 0.05 mm at hold 1, then 0.05 mm at hold 0.5, each a full sweep.py run compared with REF/sp.npz.
# LIB_DIR holds libopenEMS.0.dylib, libCSXCAD.0.dylib and libnf2ff.0.dylib of a fork build (the probe end criterion);
# RFSIM_PATH names the rfsim toolkit with its mesh floor (toolkit commit 2b0fd8c or later; the toolkit is not public).
# REF (default ../probe_end/s_ref) is the full 10 ns run on the 0.02 mm mesh made as scripts/README.md says. The first
# table (2026-11-01) came from the first version of the floor, which the corrected floor of 2b0fd8c replaced: its
# 0.03 mm row was not rerun, and the toolkit refuses 0.06 mm (0.0526 mm and above).
# Run folders r_* and the log sweep.log go next to this script. The script sets DYLD_LIBRARY_PATH itself for each
# python3 call (a DYLD_* variable set by the caller would not reach it: macOS drops DYLD_* when it starts /bin/zsh).
if (( $# < 1 || $# > 2 )); then
  echo "usage: batch.sh LIB_DIR [REF]   (LIB_DIR: the three .0.dylib files of a fork build; REF: run folder with sp.npz)" >&2
  exit 1
fi
LIB=${1:A}
if [[ -n "$2" ]]; then REF=${2:A}; else REF=${0:A:h}/../probe_end/s_ref; REF=${REF:A}; fi
for l in libopenEMS libCSXCAD libnf2ff; do
  if [[ ! -f $LIB/$l.0.dylib ]]; then
    echo "batch.sh: $LIB lacks $l.0.dylib (dyld would load the installed library instead)" >&2
    exit 1
  fi
done
cd "${0:A:h}"
if [[ ! -f $REF/sp.npz ]]; then
  echo "batch.sh: $REF/sp.npz is missing (make the reference run first, see scripts/README.md)" >&2
  exit 1
fi
(caffeinate -i -w $$ &)
sweep() {   # sweep FLOOR HOLD OUT
  DYLD_LIBRARY_PATH=$LIB python3 -B sweep.py $1 $2 $3 $REF 2>&1 \
    | grep -E "RESULT|Traceback|Error|probe end criterion|timestep is" | tee -a sweep.log
}
for fl in 0.02 0.04 0.05; do
  sweep $fl 1.0 r_${fl}
done
sweep 0.05 0.5 r_0.05_h05
echo BATCH DONE | tee -a sweep.log
