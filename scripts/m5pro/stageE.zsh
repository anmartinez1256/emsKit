#!/bin/zsh
# Stage E: end to end on the two boards through the toolkit (FDTD.Run wall time): stock, the fork's CPU engine
# (installed = cg31), the fork's Metal engine. The stock library has no probe end, so its run goes to the full time.
source ${0:A:h}/common.zsh
E=.build/release/emskit
print "stage E start $(date '+%F %T')"; zsh $M5PRO_DIR/wait_quiet.zsh 80 6 ${GATE:-300} || print "not quiet at the start: running anyway, read the others column of every line"
for b in gcpw sma; do
  for v in "stock --lib stock" "cpu --lib installed" "gpu --lib installed --engine metal-diamond"; do
    set -- ${=v}; n=$1; shift
    $E fdtd e2e $b "$@" --quiet 70 --quiet-max 240 > $O/e2e_${b}_$n.json 2> $O/logs/e2e_${b}_$n.err
    print "e2e $b $n: exit $? | $(tail -1 $O/logs/e2e_${b}_$n.err | cut -c1-220)"
  done
done
print "stage E end $(date '+%F %T')"
