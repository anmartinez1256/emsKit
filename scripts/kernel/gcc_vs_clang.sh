#!/bin/zsh
# gcc_vs_clang.sh [GXX]: the stock and the rewritten ("clean") inner loops of kb_idx.cpp built by Apple clang and by
# GCC (GXX, default g++-16) with the same flags (-std=c++17 -O3 -DNDEBUG), one thread (KB_ONE=1), at three grid sizes
# outside the valley of ../cache_valley, five rounds alternating the order of the two builds (added 2026-11-03). Each
# line gives the two speeds (MC/s) and the hash of the stock loop's final fields: equal hashes mean that both builds
# computed the same values. A speed measurement: run it on a quiet machine. The binaries go to
# ${TMPDIR:-/tmp}/emskit_gcc.
GXX=${1:-g++-16}
HERE=${0:A:h}
W=${TMPDIR:-/tmp}/emskit_gcc
mkdir -p $W || exit 1
(caffeinate -i -w $$ &)
echo "# gcc_vs_clang.sh $(date '+%Y-%m-%d %H:%M'), $(sw_vers -productName) $(sw_vers -productVersion), $(sysctl -n machdep.cpu.brand_string)"
echo "# clang: $(clang++ --version | head -1)"
echo "# gcc:   $($GXX --version | head -1)"
clang++ -std=c++17 -O3 -DNDEBUG $HERE/kb_idx.cpp -o $W/kb_clang || exit 1
$GXX -std=c++17 -O3 -DNDEBUG $HERE/kb_idx.cpp -o $W/kb_gcc || exit 1
for r in 1 2 3 4 5; do
  if (( r % 2 )); then order=(clang gcc); else order=(gcc clang); fi
  for g in "3000 40 40 40" "400 160 160 20" "30 209 209 180"; do
    for b in $order; do
      out=$(KB_ONE=1 $W/kb_$b ${=g})
      st=$(print -r -- $out | grep 'stock, 1 thread' | grep -oE '[0-9]+ MC/s' | grep -oE '[0-9]+')
      cl=$(print -r -- $out | grep 'clean, 1 thread' | grep -oE '[0-9]+ MC/s' | grep -oE '[0-9]+')
      ok=$(print -r -- $out | grep 'clean, 1 thread' | grep -oE 'bit-identical|MISMATCH')
      hs=$(print -r -- $out | grep -oE 'hash [0-9a-f]+')
      echo "round $r  steps,grid $g  $b  stock $st  clean $cl ($ok)  $hs"
    done
  done
done
echo DONE
