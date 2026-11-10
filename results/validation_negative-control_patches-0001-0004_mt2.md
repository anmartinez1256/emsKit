# Validation negative-control_patches-0001-0004_mt2

2026-11-03T11:07:10, arm64, macOS-27.0.1-arm64-arm-64bit-Mach-O, engine multithreaded, threads 2

Libraries loaded from: ~/opt/openEMS-dev/snap/cg16

Engines reported: slab: basic, compressed SSE + multi-threading, threads 2 (fixed)

4 of 6 checks passed. Case times (s): {'slab': 3.2}

| case | quantity | value | error | tolerance | result | note |
|---|---|---|---|---|---|---|
| slab_debye | max \|R - R_exact\| over 0.5-9 GHz | 0.425033 | 0.425 | 0.03 (abs) | **FAIL** | mean 0.3459; distance from non-dispersive answer 0.00 |
| slab_debye | max \|v - v_basic\| / max \|v_basic\| (multithreaded vs basic engine) | 0.597526 | 0.598 | 0 (abs) | **FAIL** | same build; must be 0 |
| slab_drude | max \|R - R_exact\| over 0.5-9 GHz | 0.0200918 | 0.0201 | 0.03 (abs) | PASS | mean 0.0156; distance from non-dispersive answer 0.72 |
| slab_drude | max \|v - v_basic\| / max \|v_basic\| (multithreaded vs basic engine) | 0 | 0 | 0 (abs) | PASS | same build; must be 0 |
| slab_lorentz | max \|R - R_exact\| over 0.5-9 GHz | 0.0153207 | 0.0153 | 0.03 (abs) | PASS | mean 0.0088; distance from non-dispersive answer 0.77 |
| slab_lorentz | max \|v - v_basic\| / max \|v_basic\| (multithreaded vs basic engine) | 0 | 0 | 0 (abs) | PASS | same build; must be 0 |
