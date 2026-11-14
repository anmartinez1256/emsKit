#!/bin/zsh
# The fork's installed openEMS binary under upstream bench.py's `--engine cpu`, with the libraries of the snapshot named
# by FORK_SNAP (default: the installed build). --engine=cpu becomes --engine=multithreaded. DYLD_LIBRARY_PATH is set here,
# inside the script, because zsh is SIP-protected and a DYLD variable set by the caller would not arrive.
# OPENEMS_PREFIX: the install (default ~/opt/openEMS); OPENEMS_BENCH_SNAPS: the snapshot folder (default ~/opt/openEMS-dev/snap).
[[ -n $FORK_SNAP ]] && export DYLD_LIBRARY_PATH=${OPENEMS_BENCH_SNAPS:-$HOME/opt/openEMS-dev/snap}/$FORK_SNAP
args=()
for a in "$@"; do
  if [[ $a == --engine=cpu ]]; then args+=(--engine=multithreaded); else args+=("$a"); fi
done
exec ${OPENEMS_PREFIX:-$HOME/opt/openEMS}/bin/openEMS "${args[@]}"
