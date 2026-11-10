"""export_gcpw.py RUN_DIR EXPORT_DIR [AIR]: export the GCPW line's operator (one time step) with the fork's
OPENEMS_EXPORT_OPERATOR, verbose 3 to see where the time step is set; stab.py EXPORT_DIR then computes the exact
leapfrog limit (2026-11-03). Needs the toolkit (RFSIM_PATH) and a fork build."""
import os, sys
if "RFSIM_PATH" not in os.environ:
    raise KeyError("RFSIM_PATH is not set: point it at the rfsim toolkit directory (the folder that contains rfsim/)")
sys.path.insert(0, os.environ["RFSIM_PATH"])
from rfsim.openems import core
out = os.path.abspath(sys.argv[1]); exp = os.path.abspath(sys.argv[2])
air = float(sys.argv[3]) if len(sys.argv) > 3 else 4.0
os.makedirs(exp, exist_ok=True)
os.environ["OPENEMS_EXPORT_OPERATOR"] = exp
m = core.gcpw_line(length=50.0, feed=10.0, scale=1.0, f_max=2e9, f_ref=640e6, air=air)
m.fdtd.SetNumberOfTimeSteps(1)
m.fdtd.Run(out, cleanup=True, verbose=3, numThreads=2)
