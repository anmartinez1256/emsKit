"""Run upstream master's benchmark/bench.py with master's openEMS.compare (pure Python) loaded from the exported source,
since the installed user-site openEMS module (v0.37.0) has no compare submodule. Nothing is installed or changed.
usage: MASTER_DIR=DIR python3 bench_launch.py ARGS...   (the arguments of bench.py)
MASTER_DIR holds src/ (upstream master 1d710c2 and CSXCAD fdff4b5 by `git archive`, see build.zsh); default: this folder."""
import importlib.util, os, runpy, sys
here = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(os.environ.get('MASTER_DIR', here), 'src', 'openEMS')
import openEMS
spec = importlib.util.spec_from_file_location('openEMS.compare', os.path.join(src, 'python', 'openEMS', 'compare.py'))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
sys.modules['openEMS.compare'] = mod
openEMS.compare = mod
bench = os.path.join(src, 'benchmark', 'bench.py')
sys.path.insert(0, os.path.dirname(bench))   # cases.py beside bench.py
if os.environ.get('BENCH_ODD_LINES') == '1':
    # upstream's uniform meshes with an even line count (S = 100, M = 200) have no mesh line through the origin, so the
    # dipole of ideal, pml and dispersive excites nothing and all fields stay zero (found 2026-11-13). With this switch
    # even counts get one more line (S = 101, M = 201), so those cases run with a source.
    import cases
    cases.LINES = {k: v + 1 - v % 2 for k, v in cases.LINES.items()}
    print('BENCH_ODD_LINES=1: mesh lines per direction', cases.LINES)
sys.argv = [bench] + sys.argv[1:]
runpy.run_path(bench, run_name='__main__')
