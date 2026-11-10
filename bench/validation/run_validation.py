#!/usr/bin/env python3
"""emsKit validation suite: openEMS against closed-form and exact discrete references.

  python3 run_validation.py [--quick] [--cases slab cavity lines] [--work DIR] [--out DIR] [--tag TAG]

Uses whatever openEMS the current Python imports (set DYLD_LIBRARY_PATH / LD_LIBRARY_PATH to
pick a build), the engine in VALIDATION_ENGINE (default 'fastest') and VALIDATION_THREADS.
Writes validation_<TAG>.json and .md to --out (default: the top-level results/ folder) and exits
non-zero if any check fails. The files name the libraries that were loaded and the engine each
run reported, with the home directory written as '~', and no host name. See README.md for what
each case tests and why.
"""
import argparse
import datetime
import json
import os
import platform
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(1, os.path.dirname(HERE))   # bench/: libinfo.py

import case_cavity          # noqa: E402
import case_dispersive_slab  # noqa: E402
import case_lines           # noqa: E402
import common               # noqa: E402
from libinfo import loaded_libs  # noqa: E402

CASES = {'slab': case_dispersive_slab, 'cavity': case_cavity, 'lines': case_lines}


def tidy(x):
    """Home directory -> '~' in every string of a result structure."""
    if isinstance(x, dict):
        return {k: tidy(v) for k, v in x.items()}
    if isinstance(x, list):
        return [tidy(v) for v in x]
    return common.tidy(x)


def esc(s):
    """A Markdown table cell: '|' would start a new cell."""
    return str(s).replace('|', '\\|')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--quick', action='store_true',
                    help='shorter slab and cavity runs (looser frequency resolution); the lines case is the same')
    ap.add_argument('--cases', nargs='+', choices=CASES, default=list(CASES))
    ap.add_argument('--work', default=os.environ.get('VALIDATION_WORK', '/tmp/emskit_validation'))
    ap.add_argument('--tag', default=datetime.datetime.now().strftime('%Y-%m-%d_%H%M'))
    ap.add_argument('--out', default=os.path.join(HERE, '..', '..', 'results'))
    a = ap.parse_args()
    a.work, a.out = os.path.abspath(a.work), os.path.abspath(a.out)   # FDTD.Run changes the directory
    try:
        common.engine()
    except ValueError as e:
        sys.exit(f'run_validation.py: {e}')

    import openEMS
    libs = loaded_libs()
    meta = dict(tag=a.tag, date=datetime.datetime.now().isoformat(timespec='seconds'),
                machine=platform.machine(), system=platform.platform(),
                engine=os.environ.get('VALIDATION_ENGINE', 'fastest'),
                threads=os.environ.get('VALIDATION_THREADS', '0'),
                openems_module=openEMS.__file__, libraries=libs,
                lib_path=os.environ.get('DYLD_LIBRARY_PATH') or os.environ.get('LD_LIBRARY_PATH') or '(default)',
                quick=a.quick)
    results, timings, runs = [], {}, {}
    for name in a.cases:
        t0, n0 = time.time(), len(common.RUNS)
        try:
            results += CASES[name].run_case(os.path.join(a.work, name), quick=a.quick)
        except Exception as e:  # a crash is a failure, not a skipped case
            results.append(dict(case=name, quantity='ran without error', value=None, reference=None,
                                error=float('nan'), tol=0, kind='-', passed=False, note=repr(e)[:300]))
        timings[name] = round(time.time() - t0, 1)
        runs[name] = common.RUNS[n0:]
    meta, results = tidy(meta), tidy(results)

    rows = ['| case | quantity | value | error | tolerance | result | note |', '|---|---|---|---|---|---|---|']
    for r in results:
        v = '' if r['value'] is None else f"{r['value']:.6g}"
        rows.append(f"| {esc(r['case'])} | {esc(r['quantity'])} | {v} | {r['error']:.3g} | {r['tol']:g} "
                    f"({r['kind']}) | {'PASS' if r['passed'] else '**FAIL**'} | {esc(r['note'])} |")
    n_fail = sum(not r['passed'] for r in results)
    lib_dirs = sorted({os.path.dirname(p) for p in meta['libraries']}) or ['(none found)']
    engines = '; '.join(f"{c}: " + ', '.join(sorted({x['engine'] + (f", threads {x['threads']}" if x['threads'] else '')
                                                       for x in rs})) for c, rs in runs.items() if rs)
    head = (f"# Validation {a.tag}\n\n{meta['date']}, {meta['machine']}, {meta['system']}, engine {meta['engine']}, "
            f"threads {meta['threads']}{', quick' if a.quick else ''}\n\nLibraries loaded from: "
            f"{', '.join(lib_dirs)}\n\nEngines reported: {engines or '-'}\n\n"
            f"{len(results) - n_fail} of {len(results)} checks passed. Case times (s): {timings}\n\n")
    md = head + '\n'.join(rows) + '\n'
    print(md)
    os.makedirs(a.out, exist_ok=True)
    base = os.path.join(a.out, f'validation_{a.tag}')
    with open(base + '.json', 'w') as fh:
        json.dump(dict(meta=meta, timings=timings, runs=runs, results=results), fh, indent=1, default=str)
    with open(base + '.md', 'w') as fh:
        fh.write(md)
    print(f'written: {base}.json/.md')
    return 1 if n_fail else 0


if __name__ == '__main__':
    sys.exit(main())
