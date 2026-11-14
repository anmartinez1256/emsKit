#!/bin/zsh
# The fork's installed openEMS binary (cg31) under upstream bench.py's `--engine cpu`: --engine=cpu becomes
# --engine=multithreaded (the fork's CPU engine; it has no engine named cpu), every other argument passes unchanged.
# Lets bench.py interleave master's cpu engine with the fork's CPU engine run for run. OPENEMS_PREFIX: the install
# (default ~/opt/openEMS).
args=()
for a in "$@"; do
  if [[ $a == --engine=cpu ]]; then args+=(--engine=multithreaded); else args+=("$a"); fi
done
exec ${OPENEMS_PREFIX:-$HOME/opt/openEMS}/bin/openEMS "${args[@]}"
