"""mkresult.py OUT_DIR RESULT_FILE: assemble results/gpu_crossover_cg29_2026-11-05.txt from header.txt (beside this script,
the method text), OUT_DIR/analysis.txt (written by `analyze.py OUT_DIR > OUT_DIR/analysis.txt`) and the raw abtest records
in OUT_DIR: out/ (sweep.sh), out_pass1/ (the first pass of patch scales 2.5 and 3) and out_len/ (the run-length check of
section 5; both made with bench/abtest.py by hand, as the record's header says). The text of sections 2, 3 and 5 is
written here from the analysis of 2026-11-05, so new data needs new text."""
import glob, os, sys
X, OUT = sys.argv[1], sys.argv[2]
A = open(os.path.join(X, 'analysis.txt')).read().splitlines()
table = [l for l in A if l.startswith('# |')]
cross = [l for l in A if l.startswith('# crossover') or l.startswith('# every round')]
checks = [l for l in A if l.startswith('# checks') or l.startswith('# GPU port') or l.startswith('#   ') or
          l.startswith("# bench.py's") or l.startswith('# TIMING=1')]
P = []
P.append(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'header.txt')).read().rstrip('\n'))
P.append('#\n# 1. Per point (rows by model, then cells)')
P += table
P.append('''#
# 2. Where the GPU overtakes the CPU. There is no single size. The GPU is ahead in every round from 1.7 M cells on the
# notch filter, 2.4 M on the GCPW line and 2.9 M on the patch antenna (medians x1.10-1.52 from there, x1.25-1.52 from
# 3.1 M cells on); the medians cross for the last time at about 0.66, 1.45 and 1.91 M cells. Below that the two engines
# are within x0.89-1.23 of each other and the side depends on the model: the GPU leads on the GCPW line at 0.11-0.42 M
# cells (x1.03-1.23), trails on the notch filter (x0.89 at 0.27 M) and changes sides on the patch antenna (x0.94-1.11 up
# to 1.85 M). On grids that small the session moves the ratio as well (section 5).''')
P += cross
P.append('''#
# 3. Why the GPU's lead narrows on small grids, or turns into a loss (the c3 columns of section 1):
# (a) It waits for the CPU. Between IterateTS calls the CPU records the probes and evaluates the dumps while the GPU
#     idles ("outside"), and starting and finishing a call's command buffers leaves it idle too ("gaps"): 0.30-0.50 ms
#     per call on the smallest grids. On the patch antenna at scale 1 (the patch tutorial) a call ends every 31 steps,
#     at the nf2ff dumps, and holds 1.27 ms of GPU work, so the GPU is busy 81 % of the loop (79-82 % per run here,
#     73-79 % in the later runs of section 5); 94 % at 0.62 M cells, 98-99 % from 4.2 M. On the patch antenna, up to
#     0.62 M cells, its rate over busy time alone (GPU-only, 2413-2898 MC/s) is above the CPU's at every point
#     (1766-2825): on those grids the waiting decides. The notch filter and the GCPW line end a call every 81-750 steps
#     and keep the GPU busy 97-99 % at every size.
# (b) Its own rate is lower on small grids: GPU-only 1959 MC/s on the notch filter at 0.27 M cells against 3239 at 5.2
#     M, 1799-1956 on the GCPW line at 0.11-0.16 M against 3053 at 5.1 M. A dispatch there has few tiles for the 10 GPU
#     cores (notch filter at 0.27 M: 75-96 tiles of 256 threads; GCPW line at 0.11 M: 18-30) and short columns (4
#     z-vectors), and the edge work makes up more of the cells (the 8-cell PML and the Mur faces on the notch filter,
#     the conducting sheets and the Mur faces on the GCPW line). These causes were not separated; the patch antenna at
#     0.10 M cells (16-25 tiles of 256 threads, 12 z-vectors) ran 2510 MC/s over busy time.
# (c) The CPU is at its best in the middle of the range: 1573-2208 MC/s at 0.10-0.27 M cells, 2570-3003 at 0.62-1.85 M,
#     above the 2273 MC/s the cores reach from DRAM (paper, section "Where the ceiling is": one independent sub-grid per
#     thread, 111 GB/s at 49 B per cell), presumably because the caches then carry part of the traffic (not measured),
#     and 1919-2263 at 4.2-7.9 M cells, at or below that ceiling, while the GPU runs 2818-3220 there.''')
P.append('#\n# 4. Checks')
P += checks
P.append('''#
# 5. Run length and session: the patch tutorial (scale 1, 0.104 M cells) at the bench's 10 500 steps (the speed table's
# count, x0.93 there) and at the sweep's 36 500, paired in one session four hours after the sweep's point (16:32-16:37,
# others 0.3-0.7 cores), each twice; configs c0 multithreaded:8, c1 metal-diamond, c2 metal-diamond with TIMING=1.
#   10 500 steps: x0.929 [0.912-0.956] and x0.907 [0.892-0.948]; CPU 1887 and 1926 MC/s, GPU 1740 and 1735.
#   36 500 steps: x0.972 [0.929-0.973] and x0.953 [0.937-0.978]; CPU 1910 and 1904 MC/s, GPU 1852 and 1819.
#   The sweep's point (36 500 steps, 12:29-12:37): x1.107 [1.090-1.169]; CPU 1766, GPU 1956.
#   TIMING runs (per run): busy 74-79 % at 10 500 steps and 73-76 % at 36 500 (the sweep's 79-82 %); GPU-only 2184-2254
#   and 2421-2465 MC/s (sweep 2443-2515); outside 10-14 % and 12-15 % (sweep 8-10 %); gaps 11-12 % in all.
# So the run length moves this ratio by about 4 % (the GPU's own rate is 10 % lower in the shorter runs), and the session
# by 14-16 % (in the later session the CPU ran 8 % faster, and the CPU's work between the GPU's calls took longer, so the
# GPU waited more): on grids this small the two engines are close, and which one leads depends on the session.''')
P.append('#\n# Raw output (bench/abtest.py), file by file: the sweep (out/), the first pass of patch scales 2.5 and 3 (replaced by\n# the re-runs above), the run-length check.')
for d, tag in (('out', ''), ('out_pass1', ' (first pass, replaced)'), ('out_len', ' (run-length check)')):
    for f in sorted(glob.glob(os.path.join(X, d, '*.txt')), key=lambda f: (open(f).readline()[-200:].split('  ')[1] if '  ' in open(f).readline() else '', f)):
        P.append(f'# ---- {d}/{os.path.basename(f)}{tag}')
        P.append(open(f).read().rstrip('\n'))
open(OUT, 'w').write('\n'.join(P) + '\n')
print('wrote', OUT, sum(1 for _ in open(OUT)), 'lines')
