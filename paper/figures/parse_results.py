"""Collect the best engine speed per (model, snapshot) from results/*.txt into results/summary.json.
Row format: 'CFG   1234.5 MC/s  ...  others  NN%  ...'. CFG is 'SNAP@ENGINE...' for a snapshot run and 'stock@...' for the
stock v0.37.0 reference; a plain engine name is the library installed at the time (stock v0.37.0 in the step-1 tables,
which step1.sh now writes with stock@ rows; both forms count as the stock sweep there).
A row counts for the snapshot of its table, with one exception: the A@ rows of the *_AB.txt tables are snapshot A (the
cg14 tables label their own rows 'cgy@'; they count for cg14). 'best' is the fastest CPU row with dumps on (gpu,
metal-diamond, nodumps and FUSED=0 rows are left out; in the step-1 tables only the multithreaded rows count).
'stock_ref' is the fastest stock row: in the step-1 tables the stock engines themselves, elsewhere the table's stock@
row, which for the two boards is one 4-thread run (their stock thread count was never swept). 'picked' is the thread
count the automatic choice printed in the snapshot's 'fastest' row (None when the run ended before the search did).
'bad_load' names the rows whose load figure ('others') is invalid; their speed is kept (load can only slow a run), but
it is not a trusted comparison.
Files are keyed by (model, scale, nrts, tag); when a snapshot was run with more than one step count (kgcpw cg12: 15000 and
30000 steps, the second on a loaded machine) the per-(model, snapshot) 'best' and 'stock_ref' are the maxima over those files,
'nrts', 'rows' and 'picked' are the file that gave the best, and 'runs' keeps every file by its step count.
The cg17 tables are the correctness check of patch 0005, run while the machine was loaded: they are collected like the
others but are not speed results. The cg18 tables are the full check of snapshot cg18 (patches 0001-0006, quiet
machine, 2026-11-03); notch_s1_n3000_ftzgpu.txt (2026-11-03, loaded machine) is a correctness check of OPENEMS_FTZ
against the GPU engine, not a speed result. 'stock_ref' leaves out stock rows with the dumps off. The *_base.txt
tables (2026-11-03) compare stock, the fork's base (upstream gpu-engine 7bb294f, 'base@' rows) and cg18 on the same
runs: only their base@ rows count for 'base' (best), their stock@ rows for its stock_ref; their cg18@ rows are kept in
'rows' but count for nothing. The tables after cg18 were first collected on 2026-11-07. Like the cg17 tables they are
correctness checks with unpaired runs, many of them on a loaded machine, not speed results: cg19, cg21 and cg22 are
reduced checks (4 and 8 threads, the automatic count and a metal-diamond row), cg29 and cg29pre full checks, pub29
the full check of a build of the published patches from a fresh clone (2026-11-07), and the *_cg2Ngpu.txt (cg20 to
cg29) and *_pub29gpu.txt tables the Metal diamond engine against the multithreaded engine with OPENEMS_FTZ=1 (cg20 to
cg22 also with a row of the base's GPU engine), where 'best' is the multithreaded row. patch_s1_n10500_cg10gpu.txt
(2026-10-29) is the base's GPU engine of cg10 against stock: it has no row of the fork's CPU engine, so its 'best' is
0.0. The paired speed results of cg29 and of the Metal engine are in speed_cg29_2026-11-05.txt,
cpu_items_cg29_2026-11-05.txt and the diamond_engine_*_2026-11-04.txt files."""
import glob, json, os, re
R = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "results")
row = re.compile(r"^(\S+)\s+([0-9.]+) MC/s")
load = re.compile(r"others\s+(-?\d+)%")
pick = re.compile(r"auto-picked (\d+) threads")
files = {}
for fn in sorted(glob.glob(os.path.join(R, "*_*.txt"))):
    base = os.path.basename(fn)[:-4]
    m = re.match(r"(patch|notch|kgcpw|ksma)_s(\d+(?:\.\d+)?)_n(\d+)_(.+)$", base)
    if not m:
        continue
    model, scale, nrts, tag = m.group(1), m.group(2), int(m.group(3)), m.group(4)
    snaps = {}
    for line in open(fn):
        mm = row.match(line)
        if not mm:
            continue
        cfg, mc = mm.group(1), float(mm.group(2))
        snap = "A" if tag == "AB" and cfg.startswith("A@") else tag
        e = snaps.setdefault(snap, {"best": 0.0, "stock_ref": 0.0, "rows": {}, "picked": None, "bad_load": []})
        e["rows"][cfg] = mc
        if tag == "base" and not cfg.startswith(("base@", "stock@")):
            continue
        ld = load.search(line)
        if ld and not 0 <= int(ld.group(1)) <= 1000:          # 10 cores: 0..1000 % of one core
            e["bad_load"].append(cfg)
        if tag == "step1":            # the stock sweep: plain rows, or stock@ rows (step1.sh runs the stock snapshot)
            eng = cfg[len("stock@"):] if cfg.startswith("stock@") else cfg
            if "@" not in eng and not eng.startswith(("basic", "sse")):
                e["stock_ref"] = max(e["stock_ref"], mc)
            if "@" not in eng and eng.startswith("multithreaded") and "nodumps" not in eng:
                e["best"] = max(e["best"], mc)
        elif cfg.startswith("stock@"):
            if "nodumps" not in cfg:
                e["stock_ref"] = max(e["stock_ref"], mc)
        elif "nodumps" not in cfg and "gpu" not in cfg and "metal-diamond" not in cfg and "FUSED=0" not in cfg:
            e["best"] = max(e["best"], mc)
        pk = pick.search(line)
        if pk and cfg.split("@")[-1] == "fastest" and not cfg.startswith("stock@"):
            e["picked"] = int(pk.group(1))
    for snap, e in snaps.items():
        files[(model, scale, nrts, snap)] = e
out = {}
for (model, scale, nrts, tag), r in sorted(files.items()):
    key = model if float(scale) == 1 else f"{model}_x{scale}"
    e = out.setdefault(key, {}).setdefault(tag, {"best": 0.0, "stock_ref": 0.0, "nrts": nrts, "rows": {}, "picked": None,
                                                  "runs": {}})
    e["runs"][str(nrts)] = r
    e["stock_ref"] = max(e["stock_ref"], r["stock_ref"])
    if r["best"] >= e["best"]:
        e["best"], e["nrts"], e["rows"], e["picked"] = r["best"], nrts, r["rows"], r["picked"]
json.dump(out, open(os.path.join(R, "summary.json"), "w"), indent=1)
order = ["step1", "base", "A", "AB", "ABCDEG", "cg2", "cg6", "cg8", "cg9", "cg10", "cg11", "cg12", "cg13", "cg14", "cg18"]
for key, tags in out.items():
    print(key, "  ".join(f"{t}:{tags[t]['best']:.0f}" for t in order if t in tags)
          + (f"   cg17 (correctness check, loaded machine): {tags['cg17']['best']:.0f}" if "cg17" in tags else ""))
