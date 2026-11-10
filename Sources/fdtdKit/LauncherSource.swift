// SPDX-License-Identifier: GPL-3.0-or-later

// The Python launcher (spec 13), embedded byte for byte: Python/fdtdkit_run.py is excluded from the target, its exact
// bytes live here, and a test checks that the two are equal. Each run writes it to RUN/fdtdkit_run.py
// (FdtdRunFolders.writeLauncher) and records its sha256 in outputs.
import Foundation

/// The embedded launcher and its argv prefix.
enum FdtdLauncherSource {
    static let fileName = "fdtdkit_run.py"
    /// The launcher reads the control pipe on this fd.
    static let controlFd: Int32 = 3

    /// The exact bytes of Python/fdtdkit_run.py (regenerate this literal whenever the .py changes; the test
    /// compares the two).
    static let source = #"""
# SPDX-License-Identifier: GPL-3.0-or-later
"""fdtdKit's launcher for `emskit fdtd` (spec 13): runs one tool and writes a report that the CLI reads.

  fdtdkit_run.py --repo REPO --report FILE --control-fd FD [--load] [--calls] [--engine E] [--threads N]
                 [--nodumps] {script|exec} -- TARGET [ARGS...]

script  runs the Python file TARGET in this process, as `python3 TARGET ARGS` would, with a shim around
        openEMS.openEMS.Run: --engine, --threads and --nodumps go into every FDTD.Run call, and with --calls
        each call is recorded and framed by FDTDKIT_CALL_BEGIN/END lines on the original stdout.
exec    runs TARGET ARGS as a child in this process group and waits for it.

FD is the read end of a pipe whose only write end the CLI holds. A `stop` line, or EOF when the CLI is gone,
is a stop request: script mode aborts the openEMS runs in progress (SetAbort) or interrupts the script; exec
mode sends SIGTERM to the process group, whose TERM handler here does nothing, so the report is still written.
After EOF the group gets SIGKILL 30 s later if it still runs. --load samples the CPU and GPU use of the whole
run with REPO/bench/usage.py. The report, written atomically to FILE, holds the exit, whether a stop was
requested, the loads, the loaded openEMS libraries, the binding and the calls.
"""
import _thread
import argparse
import ctypes
import importlib.util
import json
import os
import runpy
import signal
import subprocess
import sys
import threading
import time
import traceback

INTEGER_OPTIONS = ('verbose', 'numthreads')   # the binding passes these on as numbers, never as True/False (F9)
PROBE_END = ('OPENEMS_PROBE_END_DB', 'OPENEMS_PROBE_END_HOLD')
TEXT_LIMIT = 1000

ARGS = None         # the launcher's own options
MODE = None         # 'script' or 'exec'
COMMAND = []        # TARGET + ARGS
CTL = None          # the control fd
MARK_FD = None      # a copy of the original fd 1: the markers go there
STDOUT_ID = None    # (st_dev, st_ino) of the original fd 1
LIBC = None
USAGE = None        # REPO/bench/usage.py as _fdtdkit_usage
LIBINFO = None      # REPO/bench/libinfo.py as _fdtdkit_libinfo
REP = {}
STOP = threading.Event()
LOCK = threading.Lock()   # orders a stop request against FDTD.Run's entry and exit and the exec child's start
STATE = dict(running={}, finishing=False, child=None, next_call=0, sampler=None, t0=None, measured=False)


def parser():
    ap = argparse.ArgumentParser(prog='fdtdkit_run.py', allow_abbrev=False,
                                 description="fdtdKit's launcher: runs one tool for emskit fdtd and writes a report.")
    ap.add_argument('--repo', required=True, help='the tools tree (REPO/bench/usage.py, libinfo.py)')
    ap.add_argument('--report', required=True, help='the report file, written atomically at the end')
    ap.add_argument('--control-fd', type=int, required=True, help='read end of the control pipe')
    ap.add_argument('--load', action='store_true', help='sample the CPU and GPU use over the whole run')
    ap.add_argument('--calls', action='store_true', help='script mode: record every FDTD.Run call')
    ap.add_argument('--engine', help='script mode: engine= in every FDTD.Run call')
    ap.add_argument('--threads', type=int, help='script mode: numThreads= in every FDTD.Run call')
    ap.add_argument('--nodumps', action='store_true', help='script mode: disable_dumps=True in every FDTD.Run call')
    ap.add_argument('mode', choices=('script', 'exec'))
    return ap


def write_all(fd, data):
    while data:
        data = data[os.write(fd, data):]


def note(text):
    """One line on stderr, which the CLI copies into tool.log."""
    try:
        write_all(2, ('fdtdkit_run: ' + text + '\n').encode('utf-8', 'replace'))
    except OSError:
        pass


def load_libc():
    try:
        libc = ctypes.CDLL(None)
        libc.fflush.argtypes = [ctypes.c_void_p]
        libc.fflush.restype = ctypes.c_int
        return libc
    except Exception:
        return None


def flush():
    """C stdio (openEMS's cout goes through it) and then Python's streams, so a marker follows what came before."""
    if LIBC is not None:
        try:
            LIBC.fflush(None)
        except Exception:
            pass
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.flush()
        except Exception:
            pass


def mark(text):
    flush()
    if MARK_FD is None:
        return
    try:
        write_all(MARK_FD, (text + '\n').encode())
    except OSError:
        pass


def same_stdout():
    """Whether fd 1 is still the file it was at the start (a script can redirect it around FDTD.Run)."""
    try:
        st = os.fstat(1)
    except OSError:
        return False
    return (st.st_dev, st.st_ino) == STDOUT_ID


def text(value):
    """repr() for the report, capped: an array's repr can be long."""
    try:
        r = repr(value)
    except Exception:
        r = '<' + type(value).__name__ + '>'
    return r if len(r) <= TEXT_LIMIT else r[:TEXT_LIMIT] + '...'


def truth(value):
    try:
        return bool(value)
    except Exception:
        return False


def load_tool(name, private):
    """REPO/bench/NAME.py as module `private`; its plain name never enters sys.modules, so a user module
    named like it cannot clash."""
    path = os.path.join(ARGS.repo, 'bench', name + '.py')
    try:
        spec = importlib.util.spec_from_file_location(private, path)
        module = importlib.util.module_from_spec(spec)
        sys.modules[private] = module
        spec.loader.exec_module(module)
        return module
    except Exception as e:
        sys.modules.pop(private, None)
        note(f'cannot load {path}: {type(e).__name__}: {e}')
        return None


def start_sampler():
    if USAGE is None:
        return None
    try:
        return USAGE.Sampler()
    except Exception as e:
        note(f'usage.Sampler failed: {type(e).__name__}: {e}')
        return None


def stop_sampler(sampler):
    """(load, loadCounts); (None, None) without a sampler."""
    if sampler is None:
        return None, None
    try:
        load = sampler.stop()
    except Exception as e:
        note(f'usage.Sampler.stop failed: {type(e).__name__}: {e}')
        load = None
    counts = dict(processesSeen=len(getattr(sampler, 'cpu1', {})), gpuClientsSeen=len(getattr(sampler, 'gpu1', {})),
                  utilSamples=len(getattr(sampler, 'util', [])))
    return load, counts


def signal_group(signo):
    """signo to this process group when the launcher leads it (the CLI spawns it so); run by hand inside some
    other group, only to the exec child and to itself."""
    try:
        if os.getpgrp() == os.getpid():
            os.killpg(os.getpgrp(), signo)
            return
        child = STATE['child']
        if child is not None and child.poll() is None:
            child.send_signal(signo)
        if signo == signal.SIGKILL:
            os.kill(os.getpid(), signo)
    except OSError:
        pass


def request_stop():
    """A stop request. Script mode: SetAbort on every openEMS instance inside FDTD.Run (openEMS ends the time loop
    at its next check, F18), or KeyboardInterrupt in the main thread when none is. No OS signal reaches openEMS,
    whose setup installs a force-exit SIGINT handler. Exec mode: SIGTERM to the group."""
    with LOCK:
        if STOP.is_set():
            return
        STOP.set()
        live = list(STATE['running'].values())
        if MODE == 'exec':
            signal_group(signal.SIGTERM)
        elif not live and not STATE['finishing']:
            _thread.interrupt_main()
    for inst in live:
        try:
            inst.SetAbort(True)
        except Exception as e:
            note(f'SetAbort failed: {type(e).__name__}: {e}')


def watchdog():
    seen = b''
    while True:
        try:
            b = os.read(CTL, 64)
        except InterruptedError:
            continue
        except OSError:
            b = b''
        seen = (seen + b)[-8:]
        if b'stop' in seen or not b:
            try:
                request_stop()
            except Exception as e:
                note(f'stop request failed: {type(e).__name__}: {e}')
        if not b:   # EOF: the CLI is gone and nobody else escalates
            time.sleep(30)
            signal_group(signal.SIGKILL)
            return


def ignore_signal(signo, frame):
    pass


def enter_run(inst):
    """Registers an instance inside FDTD.Run for the watchdog; after a stop no new run starts."""
    with LOCK:
        if STOP.is_set():
            raise KeyboardInterrupt
        STATE['running'][id(inst)] = inst


def leave_run(inst):
    with LOCK:
        STATE['running'].pop(id(inst), None)
        stopped = STOP.is_set()
    if stopped:   # FDTD.Run returns normally after an abort (F18): the script must not go on with that run
        raise KeyboardInterrupt


def norm(name):
    """How the binding (_ to -) and Boost (case-insensitive) see an option name (F19)."""
    return str(name).replace('_', '-').lower()


def ends_list(name, value):
    """Whether the legacy binding turns this option into "", which ends the option list (F9): False always, and
    a value equal to 0 (but not to 1) unless it is an integer option."""
    if norm(name) in INTEGER_OPTIONS:
        return value is False
    try:
        return bool(value == 0) and not bool(value == 1)
    except Exception:
        return False


def options_lost(options):
    lost, empty = [], False
    for name, value in options.items():
        if empty:
            lost.append(name)
        elif ends_list(name, value):
            empty = True
    return lost


def legacy_binding(module):
    """Whether the binding beside the loaded module turns a False/0 option into "" (F19). Without a pyx there
    that can be read, the installed v0.37.0 behaviour is assumed (the CLI's python probe has the same rule)."""
    pyx = os.path.join(os.path.dirname(getattr(module, '__file__', None) or ''), 'openEMS.pyx')
    try:
        with open(pyx, encoding='utf-8', errors='replace') as fh:
            return 'opt = ""' in fh.read()
    except OSError:
        return True


def binding_version(package):
    """The version of the package metadata named openEMS, taken only when one of that distribution's files lies
    in the imported package's folder: the name alone can belong to another installed copy. Else None (the
    CLI's python probe has the same rule)."""
    try:
        import importlib.metadata
        here = os.path.realpath(os.path.dirname(package.__file__))
        dist = importlib.metadata.distribution('openEMS')
        if any(os.path.dirname(os.path.realpath(str(dist.locate_file(f)))) == here for f in dist.files or []):
            return dist.version
    except Exception:
        pass
    return None


def cli_options():
    """The options injected into every FDTD.Run call, placed first (F9)."""
    applied = {}
    if ARGS.engine is not None:
        applied['engine'] = ARGS.engine
    if ARGS.threads is not None:
        applied['numThreads'] = ARGS.threads
    if ARGS.nodumps:
        applied['disable_dumps'] = True   # never False: on the legacy binding False would end the option list
    return applied


def install_shim():
    """Swaps openEMS.openEMS for a subclass whose Run injects the CLI's options, tracks the running instances for
    the watchdog and, with --calls, records each call between two markers. rfsim's `from openEMS import openEMS`
    inside its functions and a script's module-level import both come after the swap."""
    try:
        import openEMS  # loads the libraries the environment selects
        module = importlib.import_module('openEMS.openEMS')
        base = module.openEMS
        if not isinstance(base, type):
            raise TypeError('openEMS.openEMS.openEMS is not a class')
    except Exception as e:
        note(f'openEMS shim not installed: {type(e).__name__}: {e}')
        return
    legacy = legacy_binding(module)
    REP['binding'] = dict(version=binding_version(openEMS), legacyEmptyOption=legacy)
    applied = cli_options()
    mine = {norm(name): name for name in applied}

    def call(inst, sim_path, cleanup, setup_only, kw):
        sp = os.path.abspath(sim_path)   # before Run changes into it (F19)
        overridden, rest = {}, {}
        for name, value in kw.items():
            if norm(name) in mine:   # every spelling of an injected option goes; two spellings would raise (F19)
                overridden[name] = dict(script=text(value), cli=text(applied[mine[norm(name)]]))
            else:
                rest[name] = value
        lost = options_lost(rest) if legacy else []
        options = dict(applied)
        options.update(rest)
        if not ARGS.calls:
            return base.Run(inst, sp, cleanup=cleanup, setup_only=setup_only, **options)
        with LOCK:
            k = STATE['next_call']
            STATE['next_call'] = k + 1
        redirected = not same_stdout()
        mark(f'FDTDKIT_CALL_BEGIN {k}')
        sampler = start_sampler()
        t0 = time.monotonic()
        try:
            return base.Run(inst, sp, cleanup=cleanup, setup_only=setup_only, **options)
        finally:
            flush()
            wall = time.monotonic() - t0
            load, counts = stop_sampler(sampler)
            REP['calls'].append(dict(
                index=k, simPath=os.fsdecode(sp), setupOnly=truth(setup_only),
                options={name: text(value) for name, value in options.items()},
                applied={name: text(value) for name, value in applied.items()},
                overridden=overridden, optionsLost=lost, stdoutRedirected=redirected or not same_stdout(),
                wallSeconds=wall, load=load, loadCounts=counts, stopRequested=STOP.is_set(),
                probeEnd={name: os.environ.get(name) for name in PROBE_END}))
            mark(f'FDTDKIT_CALL_END {k}')

    class _FdtdKitOpenEMS(base):
        """openEMS with the CLI's options in every Run (fdtdKit launcher)."""

        def Run(self, sim_path, cleanup=False, setup_only=False, **kw):
            enter_run(self)
            try:
                return call(self, sim_path, cleanup, setup_only, kw)
            finally:
                leave_run(self)

    module.openEMS = _FdtdKitOpenEMS
    package = sys.modules.get('openEMS')
    if package is not None and getattr(package, 'openEMS', None) is base:
        package.openEMS = _FdtdKitOpenEMS


def exit_code(code):
    """SystemExit's code as Python itself exits with it: None 0, an int as given, anything else printed and 1."""
    if code is None:
        return 0
    if isinstance(code, int):
        return code & 0xFF if -2**63 <= code < 2**63 else 255
    try:
        print(code, file=sys.stderr)
    except Exception:
        pass
    return 1


def report_exception(e, target):
    """The traceback as Python prints it for the script (from the script's own first frame on), and its text."""
    try:
        REP['exception'] = f'{type(e).__name__}: {e}'
    except Exception:
        REP['exception'] = type(e).__name__
    tb = e.__traceback__
    while tb is not None and tb.tb_frame.f_code.co_filename != target:
        tb = tb.tb_next
    # the hook prints the exception's own traceback, not its tb argument; TARGET's own syntax error has no frame
    # of the script, and Python prints none for it either
    if tb is not None or isinstance(e, SyntaxError):
        e.__traceback__ = tb
    try:
        sys.excepthook(type(e), e, e.__traceback__)
    except Exception:
        traceback.print_exception(type(e), e, e.__traceback__)


def run_script():
    target = COMMAND[0]
    sys.argv = list(COMMAND)
    here = os.path.dirname(os.path.abspath(target))
    if sys.path and not getattr(sys.flags, 'safe_path', False):
        sys.path[0] = here
    else:
        sys.path.insert(0, here)
    try:
        install_shim()   # after sys.path: the binding resolves as it would for the script itself
        runpy.run_path(target, run_name='__main__')
        return 0
    except SystemExit as e:
        return exit_code(e.code)
    except KeyboardInterrupt:
        raise
    except BaseException as e:
        report_exception(e, target)
        return 1


def run_exec():
    with LOCK:
        if STOP.is_set():
            note(f'stop requested before {COMMAND[0]} started')
            return 130
        try:
            STATE['child'] = subprocess.Popen(COMMAND, close_fds=True)
        except OSError as e:
            REP['exception'] = f'{type(e).__name__}: {e}'
            note(f'cannot start {COMMAND[0]}: {e}')
            return 127 if isinstance(e, FileNotFoundError) else 126 if isinstance(e, PermissionError) else 1
    rc = STATE['child'].wait()
    return rc if rc >= 0 else 128 - rc


def interrupted():
    REP['interrupted'] = True
    return 130


def write_report():
    tmp = ARGS.report + '.tmp'
    try:
        with open(tmp, 'w', encoding='utf-8') as fh:
            json.dump(REP, fh, indent=1, default=str)
            fh.write('\n')
        os.replace(tmp, ARGS.report)
    except (OSError, TypeError, ValueError) as e:
        note(f'cannot write {ARGS.report}: {type(e).__name__}: {e}')


def finish(code):
    with LOCK:
        STATE['finishing'] = True
    flush()
    if not STATE['measured']:
        STATE['measured'] = True
        if STATE['t0'] is not None:
            REP['wallSeconds'] = time.monotonic() - STATE['t0']
        sampler, STATE['sampler'] = STATE['sampler'], None
        REP['load'], REP['loadCounts'] = stop_sampler(sampler)
    REP['exit'] = code
    REP['interrupted'] = bool(REP['interrupted'] or STOP.is_set())
    if LIBINFO is not None:
        try:
            REP['libraries'] = [str(p) for p in LIBINFO.loaded_libs()]
        except Exception as e:
            note(f'libinfo.loaded_libs failed: {type(e).__name__}: {e}')
    write_report()


def main():
    global ARGS, MODE, COMMAND, CTL, MARK_FD, STDOUT_ID, LIBC, USAGE, LIBINFO, REP
    argv = sys.argv[1:]
    if '--' not in argv:
        parser().print_usage(sys.stderr)
        note('missing -- before TARGET')
        sys.exit(2)
    cut = argv.index('--')
    ARGS = parser().parse_args(argv[:cut])
    COMMAND = argv[cut + 1:]
    if not COMMAND:
        parser().error('missing TARGET after --')
    MODE = ARGS.mode
    LIBC = load_libc()
    try:
        MARK_FD = os.dup(1)   # non-inheritable, like every fd Python creates
        st = os.fstat(MARK_FD)
        STDOUT_ID = (st.st_dev, st.st_ino)
    except OSError:
        MARK_FD = None
    CTL = ARGS.control_fd
    try:
        os.fstat(CTL)
        os.set_inheritable(CTL, False)
    except OSError:
        note(f'control fd {CTL} is not open: no stop request can reach this run')
        CTL = None
    REP = dict(mode=MODE, target=COMMAND[0], argv=list(COMMAND), exit=None, interrupted=False, exception=None,
               wallSeconds=0.0, load=None, loadCounts=None, libraries=[], dyld=os.environ.get('DYLD_LIBRARY_PATH'),
               python=dict(executable=sys.executable or '', version=sys.version.split()[0]), binding=None, calls=[])
    code = 1
    try:
        try:
            if ARGS.load or (ARGS.calls and MODE == 'script'):
                USAGE = load_tool('usage', '_fdtdkit_usage')
            if MODE == 'script':
                LIBINFO = load_tool('libinfo', '_fdtdkit_libinfo')
            STATE['t0'] = time.monotonic()
            if ARGS.load:   # one sampler over the whole run; none without --load, so none disturbs a benchmark
                STATE['sampler'] = start_sampler()
            if MODE == 'exec':   # handlers, unlike SIG_IGN, do not survive exec: the child gets the defaults
                for signo in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
                    signal.signal(signo, ignore_signal)
            if CTL is not None:
                threading.Thread(target=watchdog, name='fdtdkit-watchdog', daemon=True).start()
            code = run_script() if MODE == 'script' else run_exec()
        except KeyboardInterrupt:
            code = interrupted()
    except KeyboardInterrupt:   # a second interrupt while the first was handled
        code = interrupted()
    for _ in range(3):   # an interrupt that was already pending can land in here; the report is rewritten
        try:
            finish(code)
            break
        except KeyboardInterrupt:
            code = interrupted()
    sys.exit(code)   # the script's atexit handlers still run


if __name__ == '__main__':
    main()

"""#

    /// LCH(ROLE) of spec 5.2: `[PY, -u, -B, L, --repo, R, --control-fd, 3, --report, RUN/launcher-ROLE.json]`.
    static func argvPrefix(python: String, launcher: String, repo: String, report: String) -> [String] {
        [python, "-u", "-B", launcher, "--repo", repo, "--control-fd", String(controlFd), "--report", report]
    }
}
