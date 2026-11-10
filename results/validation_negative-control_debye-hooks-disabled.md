# Validation negative-control_debye-hooks-disabled

2026-11-03T06:40:51, vm (x86_64), engine fastest, threads 0, library /opt/openEMS-bug/lib:/opt/openEMS/lib

Note (2026-11-03, final review): made on 2026-11-03 on the same Linux x86_64 virtual machine, with a stock v0.37.0
build whose two public Debye engine hooks return early (the library path /opt/openEMS-bug/lib in the .json). That
build and its change are not published, so this control cannot be rebuilt from this repository. A control from
published code would use patches 0001-0004 (before the Debye fix of 0005) with the multithreaded engine.

2 of 3 checks passed. Case times (s): {'slab': 3.2}

| case | quantity | value | error | tolerance | result | note |
|---|---|---|---|---|---|---|
| slab_debye | max \|R - R_exact\| over 0.5-9 GHz | 0.425033 | 0.425 | 0.03 (abs) | **FAIL** | mean 0.3459; distance from non-dispersive answer 0.00 |
| slab_drude | max \|R - R_exact\| over 0.5-9 GHz | 0.0200927 | 0.0201 | 0.03 (abs) | PASS | mean 0.0156; distance from non-dispersive answer 0.72 |
| slab_lorentz | max \|R - R_exact\| over 0.5-9 GHz | 0.0153205 | 0.0153 | 0.03 (abs) | PASS | mean 0.0088; distance from non-dispersive answer 0.77 |
