#!/usr/bin/env python3
"""bench.py with the engine name of luikore's Metal fork (openEMS pull request #228) added: 'metal'.

  python3 bench_ext.py <bench.py arguments>

Run it with the Python of the build under test (its own virtual environment): runner.py is started with the same
interpreter, so the run uses that build's modules and libraries. A 'metal' config is compared with the reference
but not required to match, like bench.py's GPU configs ('(tolerant)').
"""
import os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'bench'))
import bench

bench.ENGINES += ('metal',)
_is_tolerant = bench.is_tolerant
bench.is_tolerant = lambda cfg: _is_tolerant(cfg) or bench.parse_cfg(cfg)[1] == 'metal'

if __name__ == '__main__':
    bench.main()
