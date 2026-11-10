"""CPU and GPU use of this process tree and of every other process while a benchmark runs (macOS, no sudo).

Sampler() starts a thread that reads, once a second, `ps` (cumulative CPU time per process) and the GPU
clients' per-process 'accumulatedGPUTime' (ns) plus the GPU's 'Device Utilization %' from ioreg
(IOAccelerator). stop() returns the averages over the run:
  cpu_self / cpu_other   CPU % (100 = one core) of the bench process tree / of everything else
  gpu_self / gpu_other   GPU busy % from the per-process GPU time (can exceed 100 when work overlaps);
                         gpu_self_s = the bench tree's GPU seconds, a lower bound: a process's GPU client
                         disappears with its engine, so up to one interval of it is not seen
  gpu_dev                mean of the driver's Device Utilization % samples (all processes)
  busy                   the other processes above 20 % CPU or 5 % GPU, name:cpu/gpu
A process that exits between two samples loses its last second; one that starts during the run counts
from its first sample (it had used nothing before the run began). Elsewhere than macOS stop() returns None.
"""
import os, re, subprocess, sys, threading, time

_CLIENT = re.compile(r'"IOUserClientCreator" = "pid (\d+), ([^"]*)"')
_GPUT = re.compile(r'"accumulatedGPUTime"=(\d+)')
_UTIL = re.compile(r'"Device Utilization %"=(\d+)')


def _ps():
    """{pid: (ppid, cpu seconds, name)}"""
    out = subprocess.run(['ps', '-Ao', 'pid=,ppid=,time=,comm='], capture_output=True, text=True).stdout
    procs = {}
    for ln in out.splitlines():
        f = ln.split(None, 3)
        if len(f) < 4:
            continue
        days, _, hms = f[2].rpartition('-')   # [dd-][hh:]mm:ss.cc
        sec = 0.0
        for part in hms.split(':'):
            sec = sec*60 + float(part)
        procs[int(f[0])] = (int(f[1]), sec + 86400*int(days or 0), os.path.basename(f[3]))
    return procs


def _gpu():
    """({pid: GPU ns}, device utilization %)"""
    out = subprocess.run(['ioreg', '-c', 'IOAccelerator', '-r', '-l', '-w0'], capture_output=True, text=True).stdout
    per = {}
    for block in out.split('+-o ')[1:]:   # one registry object each; ioreg sorts its properties by name
        m = _CLIENT.search(block)
        if m:
            per[int(m[1])] = per.get(int(m[1]), 0) + sum(int(x) for x in _GPUT.findall(block))
    u = _UTIL.search(out)
    return per, (int(u[1]) if u else None)


class Sampler:
    def __init__(self, interval=0.5):
        self.ok = sys.platform == 'darwin'
        if not self.ok:
            return
        self.interval, self.root = interval, os.getpid()
        self.cpu0, self.cpu1, self.gpu0, self.gpu1, self.util = {}, {}, {}, {}, []
        self.names, self.mine = {}, {self.root}
        self.stop_ev = threading.Event()
        self._sample()
        self.t0 = time.time()
        self.th = threading.Thread(target=self._loop, daemon=True)
        self.th.start()

    def _sample(self):
        procs = _ps()
        for pid, (ppid, sec, name) in procs.items():   # the bench's own tree: children of known members
            if ppid in self.mine:
                self.mine.add(pid)
        for pid, (ppid, sec, name) in procs.items():
            self.cpu0.setdefault(pid, sec if not hasattr(self, 't0') else 0.0)
            self.cpu1[pid] = sec
            self.names[pid] = name
        g, u = _gpu()
        for pid, ns in g.items():
            self.gpu0.setdefault(pid, ns if not hasattr(self, 't0') else 0)
            self.gpu1[pid] = ns
        if u is not None and hasattr(self, 't0'):
            self.util.append(u)

    def _loop(self):
        while not self.stop_ev.wait(self.interval):
            self._sample()

    def stop(self):
        if not self.ok:
            return None
        self.stop_ev.set()
        self.th.join()
        self._sample()
        dt = max(time.time() - self.t0, 1e-3)
        cpu = {p: self.cpu1[p] - self.cpu0.get(p, 0.0) for p in self.cpu1}
        gpu = {p: self.gpu1[p] - self.gpu0.get(p, 0) for p in self.gpu1}
        r = dict(cpu_self=0.0, cpu_other=0.0, gpu_self=0.0, gpu_other=0.0, wall=dt,
                 gpu_dev=sum(self.util)/len(self.util) if self.util else None, busy=[])
        for p in set(cpu) | set(gpu):
            c, g = 100*max(cpu.get(p, 0.0), 0)/dt, 100*max(gpu.get(p, 0), 0)/1e9/dt
            if p in self.mine:
                r['cpu_self'] += c
                r['gpu_self'] += g
            else:
                r['cpu_other'] += c
                r['gpu_other'] += g
                if c > 20 or g > 5:
                    r['busy'].append(f'{self.names.get(p, "?")[:16]}:{c:.0f}/{g:.0f}')
        return r


def fmt(r):
    if not r:
        return ''
    s = f'during {r["wall"]:.1f} s: self cpu {r["cpu_self"]:.0f}% gpu>={r["gpu_self"]*r["wall"]/100:.2f} s, ' \
        f'others cpu {r["cpu_other"]:.0f}% gpu {r["gpu_other"]:.0f}%'
    if r['gpu_dev'] is not None:
        s += f', gpu dev {r["gpu_dev"]:.0f}%'
    if r['busy']:
        s += ' [' + ','.join(r['busy']) + ']'
    return s


if __name__ == '__main__':   # python3 usage.py SECONDS: what the rest of the Mac uses right now
    s = Sampler()
    time.sleep(float(sys.argv[1]) if len(sys.argv) > 1 else 5)
    print(fmt(s.stop()))
