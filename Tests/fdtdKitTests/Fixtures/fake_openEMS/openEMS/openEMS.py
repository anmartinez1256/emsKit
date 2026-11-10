"""A stand-in for the compiled binding: Run prints its options, changes into sim_path as the binding does, and
steps in short sleeps until NrTS iterations or SetAbort(True)."""
import json
import os
import sys
import time


class openEMS:
    def __init__(self, NrTS=100, **kw):
        self.NrTS = int(NrTS)
        self.abort = False

    def SetAbort(self, flag):
        self.abort = bool(flag)

    def Run(self, sim_path, cleanup=False, setup_only=False, **kw):
        cwd = os.getcwd()
        os.makedirs(sim_path, exist_ok=True)
        os.chdir(sim_path)
        try:
            print('FAKE_RUN ' + json.dumps(dict(sim_path=sim_path, cwd=os.getcwd(), setup_only=bool(setup_only),
                                                kw=[[k, repr(v)] for k, v in kw.items()])), flush=True)
            print('Create FDTD engine (compressed SSE + multi-threading)', flush=True)
            if setup_only:
                return
            n = 0
            while n < self.NrTS and not self.abort:
                time.sleep(0.01)
                n += 1
            if self.abort:
                print(f'RunFDTD: simulation aborted after {n} timesteps (-3.00dB)', flush=True)
            print(f'Time for {n} iterations with 1000.00 cells : {0.01 * n:.2f} sec', flush=True)
        finally:
            os.chdir(cwd)
