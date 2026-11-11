"""pulse_cmp.py DIR: compare every run in DIR/<model>_* with DIR/<model>_std_full (the toolkit's pulse run to max_time)."""
import json, os, sys, numpy as np
D = sys.argv[1]
for model in ("gcpw", "sma"):
    ref = os.path.join(D, model + "_std_full")
    if not os.path.exists(ref + "/sp.npz"):
        continue
    R = np.load(ref + "/sp.npz")
    print(f"\n{model}: reference = toolkit pulse, full run; S11 at 1 GHz {20*np.log10(abs(R['S'][np.argmin(abs(R['f']-1e9)),0])):.2f} dB, "
          f"worst S11 in band {20*np.log10(abs(R['S'][:,0]).max()):.2f} dB, Z0 at 1 GHz {R['Z0'][np.argmin(abs(R['f']-1e9))].real:.3f} ohm")
    print(f"{'run':24} {'steps':>7} {'run s':>7} {'max dS21 dB':>12} {'max dS11 dB':>12} {'max d|S11| lin':>14} {'max dZ0 ohm':>12} {'max dphase S21 deg':>18}")
    for d in sorted(os.listdir(D)):
        p = os.path.join(D, d)
        if not d.startswith(model + "_") or not os.path.exists(p + "/sp.npz"):
            continue
        X = np.load(p + "/sp.npz"); r = json.load(open(p + "/result.json"))
        dB = lambda a: 20*np.log10(np.abs(a))
        d21 = np.abs(dB(X['S'][:,1]) - dB(R['S'][:,1])).max()
        d11 = np.abs(dB(X['S'][:,0]) - dB(R['S'][:,0])).max()
        l11 = np.abs(np.abs(X['S'][:,0]) - np.abs(R['S'][:,0])).max()
        dz = np.abs(X['Z0'].real - R['Z0'].real).max()
        dph = np.abs(np.angle(X['S'][:,1]/R['S'][:,1], deg=True)).max()
        print(f"{d:24} {str(r['info'].get('steps','?')):>7} {r['t_run']:7.1f} {d21:12.5f} {d11:12.4f} {l11:14.2e} {dz:12.4f} {dph:18.4f}")
