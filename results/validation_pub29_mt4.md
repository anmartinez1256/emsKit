# Validation pub29_mt4

2026-11-07T09:23:02, arm64, macOS-27.0.1-arm64-arm-64bit-Mach-O, engine multithreaded, threads 4

Libraries loaded from: $PUBCHECK/snaps/pub29

Engines reported: slab: basic, compressed SSE + multi-threading, threads 4 (fixed); cavity: compressed SSE + multi-threading, threads 4 (fixed), cylindrical mesh using sse compression + multithreading; cylindrical multi grid mesh using sse compression + multithreading, threads 4 (fixed); lines: compressed SSE + multi-threading, threads 4 (fixed)

15 of 15 checks passed. Case times (s): {'slab': 1.8, 'cavity': 41.6, 'lines': 2.9}

| case | quantity | value | error | tolerance | result | note |
|---|---|---|---|---|---|---|
| slab_debye | max \|R - R_exact\| over 0.5-9 GHz | 0.0104033 | 0.0104 | 0.03 (abs) | PASS | mean 0.0063; distance from non-dispersive answer 0.43 |
| slab_debye | max \|v - v_basic\| / max \|v_basic\| (multithreaded vs basic engine) | 0 | 0 | 0 (abs) | PASS | same build; must be 0 |
| slab_drude | max \|R - R_exact\| over 0.5-9 GHz | 0.0200918 | 0.0201 | 0.03 (abs) | PASS | mean 0.0156; distance from non-dispersive answer 0.72 |
| slab_drude | max \|v - v_basic\| / max \|v_basic\| (multithreaded vs basic engine) | 0 | 0 | 0 (abs) | PASS | same build; must be 0 |
| slab_lorentz | max \|R - R_exact\| over 0.5-9 GHz | 0.0153207 | 0.0153 | 0.03 (abs) | PASS | mean 0.0088; distance from non-dispersive answer 0.77 |
| slab_lorentz | max \|v - v_basic\| / max \|v_basic\| (multithreaded vs basic engine) | 0 | 0 | 0 (abs) | PASS | same build; must be 0 |
| cavity_rect | modes found (7 expected) | 7 | 0 | 0 (abs) | PASS | 101 110 011 111 201 210 102 |
| cavity_rect | max rel. error vs continuum | 0.000550499 | 0.00055 | 0.002 (abs) | PASS |  |
| cavity_rect | max rel. error vs exact discrete Yee | 1.55073e-08 | 1.55e-08 | 1e-07 (abs) | PASS | mean 1.4e-08 |
| cavity_cyl | modes found (6 expected) | 6 | 0 | 0 (abs) | PASS | TM010:-0.04% TE111:+0.00% TM011:-0.04% TM110:-0.16% TE211:+0.02% TE011/TM111:-0.07% |
| cavity_cyl | max rel. error vs Bessel-zero formula | 0.00158353 | 0.00158 | 0.005 (abs) | PASS |  |
| wr90 | max rel. error of beta, 8-12 GHz | 0.00087151 | 0.000872 | 0.005 (abs) | PASS |  |
| wr90 | max S11 (dB) of the PML-terminated guide | -54.055 | -24.1 | 0 (max) | PASS | pass if below the reference |
| msl | Z0 (ohm) vs Hammerstad-Jensen 47.67 | 47.6688 | 3.09e-05 | 0.02 (rel) | PASS |  |
| msl | eps_eff vs Hammerstad-Jensen 2.8758 | 2.87956 | 0.00132 | 0.01 (rel) | PASS |  |
