# Validation stock-v0.37.0_linux-sandbox

2026-11-03T06:35:45, vm (x86_64), engine fastest, threads 0, library /opt/openEMS/lib

Note (2026-11-03, final review): made on 2026-11-03 with stock openEMS v0.37.0 on a Linux x86_64 virtual machine (the
host and system fields of the .json), not with the emsKit fork. Engine "fastest" is the multithreaded engine in
v0.37.0; threads 0 is its automatic thread count.

12 of 12 checks passed. Case times (s): {'slab': 3.7, 'cavity': 127.5, 'lines': 48.6}

| case | quantity | value | error | tolerance | result | note |
|---|---|---|---|---|---|---|
| slab_debye | max \|R - R_exact\| over 0.5-9 GHz | 0.0103989 | 0.0104 | 0.03 (abs) | PASS | mean 0.0063; distance from non-dispersive answer 0.43 |
| slab_drude | max \|R - R_exact\| over 0.5-9 GHz | 0.0200927 | 0.0201 | 0.03 (abs) | PASS | mean 0.0156; distance from non-dispersive answer 0.72 |
| slab_lorentz | max \|R - R_exact\| over 0.5-9 GHz | 0.0153205 | 0.0153 | 0.03 (abs) | PASS | mean 0.0088; distance from non-dispersive answer 0.77 |
| cavity_rect | modes found (7 expected) | 7 | 0 | 0.25 (rel) | PASS | 101 110 011 111 201 210 102 |
| cavity_rect | max rel. error vs continuum | 0.000550499 | 0.00055 | 0.002 (abs) | PASS |  |
| cavity_rect | max rel. error vs exact discrete Yee | 1.54882e-08 | 1.55e-08 | 1e-06 (abs) | PASS | mean 1.4e-08 |
| cavity_cyl | modes found (6 expected) | 6 | 0 | 0.25 (rel) | PASS | TM010:-0.04% TE111:+0.00% TM011:-0.04% TM110:-0.16% TE211:+0.02% TE011/TM111:-0.07% |
| cavity_cyl | max rel. error vs Bessel-zero formula | 0.00158353 | 0.00158 | 0.005 (abs) | PASS |  |
| wr90 | max rel. error of beta, 8-12 GHz | 0.000871908 | 0.000872 | 0.005 (abs) | PASS |  |
| wr90 | max S11 (dB) of the PML-terminated guide | -54.055 | -24.1 | 0 (max) | PASS | pass if below the reference |
| msl | Z0 (ohm) vs Hammerstad-Jensen 47.67 | 47.6687 | 2.9e-05 | 0.02 (rel) | PASS |  |
| msl | eps_eff vs Hammerstad-Jensen 2.8758 | 2.87955 | 0.00131 | 0.01 (rel) | PASS |  |
