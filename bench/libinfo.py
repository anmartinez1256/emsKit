"""Paths of the openEMS libraries (libopenEMS, libCSXCAD, libnf2ff) loaded into this process.

macOS: dyld's list of loaded images; Linux: /proc/self/maps. Call it after `import openEMS`.
runner.py prints them for bench.py, which checks that a LIB@ config really ran its snapshot, and the
validation suite records them in its result files.
"""
import ctypes, os, sys

NAMES = ('libopenEMS', 'libCSXCAD', 'libnf2ff')


def _images():
    if sys.platform == 'darwin':
        dyld = ctypes.CDLL('/usr/lib/libSystem.B.dylib')
        dyld._dyld_image_count.restype = ctypes.c_uint32
        dyld._dyld_get_image_name.restype = ctypes.c_char_p
        dyld._dyld_get_image_name.argtypes = [ctypes.c_uint32]
        names = (dyld._dyld_get_image_name(i) for i in range(dyld._dyld_image_count()))
        return [n.decode() for n in names if n]
    if os.path.exists('/proc/self/maps'):
        with open('/proc/self/maps') as fh:
            return [f[5].strip() for f in (ln.split(None, 5) for ln in fh) if len(f) == 6]
    return []


def loaded_libs(names=NAMES):
    """The loaded images whose file name starts with one of `names` plus a dot, in load order."""
    out = []
    for p in _images():
        if any(os.path.basename(p).startswith(n + '.') for n in names) and p not in out:
            out.append(p)
    return out
