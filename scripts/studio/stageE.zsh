#!/bin/zsh
# Stage E (Mac Studio, M5 Max): end to end on the two boards through the toolkit (FDTD.Run wall time): stock, the installed build's
# CPU engine (cg31), cg33's CPU engine, the Metal engine. Stock has no probe end, so its run goes to the full time.
source ${0:A:h}/common.zsh; gate "stage E"
E=.build/release/emskit
for b in gcpw sma; do
  for v in "cpu --lib installed" "cpu31 --lib cg31" "gpu --lib installed --engine metal-diamond" "stock --lib stock"; do
    set -- ${=v}; n=$1; shift
    $E fdtd e2e $b "$@" --quiet 300 --quiet-max 20 > $O/e2e_${b}_$n.json 2> $O/logs/e2e_${b}_$n.err
    print "e2e $b $n: exit $? | $(tail -1 $O/logs/e2e_${b}_$n.err | cut -c1-220)"
  done
done
print "stage E end $(date '+%F %T')"
