// Swift + Metal FDTD engine prototype for openEMS operators (emsKit/swift_engine, 2026-10-29).
//
// Runs the openEMS compressed-SSE operator exported by our fork (OPENEMS_EXPORT_OPERATOR) on the GPU and writes
// the fields in the same raw format as OPENEMS_EXPORT_FIELDS, so compare.py can check it against the CPU engine.
// The kernels mirror Engine_sse::UpdateVoltages/UpdateCurrents exactly: f4vector layout (cell z = lane*numVectors+zv),
// the same operation order, fma where clang fuses "a += b*c" on arm64, and Metal fast-math off.
// Credit: the kernels follow the operation order of openEMS's Engine_sse (FDTD/engine_sse.cpp, by Thorsten Liebig).
// Only the excitation extension is implemented (soft voltage excitation, as Engine_Ext_Excitation::Apply2Voltages):
// there is no Mur, PML, lumped port or RLC, probe or openEMS dump box (only the final fields are written), and an
// export with any other extension or with current excitations is refused.
//
//   swiftc -O fdtd.swift -o fdtd_swift
//   ./fdtd_swift OP_DIR NRTS OUT_DIR [--batch N] [--nodump] [--nofma] [--diamond K [--tile M,V] [--tg T]]
// --diamond K: diamond-blocked sweep, K timesteps per tile (schedule after luikore's Metal engine, openEMS PR #228);
// --tile M,V: mountain and valley widths in cells (default 2K,2K; M >= 2K-1); --tg T: threads per threadgroup.
// --batch N: timesteps per command buffer (default 50); --nodump: no field output; --nofma: c + a*b instead of
// fma(a, b, c) (to match a CPU build that does not fuse "a += b*c").

import Foundation
import Metal

let msl = """
#pragma METAL fp contract(off)
#include <metal_stdlib>
using namespace metal;
#ifdef NOFMA
#define FMA(a,b,c) ((c) + (a)*(b))
#else
#define FMA(a,b,c) fma((a),(b),(c))
#endif

struct Dims { uint nx, ny, nv, numOps; };
struct ExcP { uint count, length, numTS, period; };

inline uint I(uint n, uint x, uint y, uint zv, constant Dims& d) { return ((n*d.nx + x)*d.ny + y)*d.nv + zv; }

kernel void updateV(device float4* volt [[buffer(0)]], device const float4* curr [[buffer(1)]],
                    device const float4* vv [[buffer(2)]], device const float4* vi [[buffer(3)]],
                    device const uint* opi [[buffer(4)]], constant Dims& d [[buffer(5)]],
                    uint3 t [[thread_position_in_grid]])
{
    const uint zv = t.x, y = t.y, x = t.z;
    if (zv >= d.nv || y >= d.ny || x >= d.nx) return;
    const uint op = opi[(x*d.ny + y)*d.nv + zv];
    const uint xm = x > 0 ? x-1 : x, ym = y > 0 ? y-1 : y;   // shift[0]/shift[1] of the CPU loop
    const float4 c0 = curr[I(0,x,y,zv,d)], c1 = curr[I(1,x,y,zv,d)], c2 = curr[I(2,x,y,zv,d)];
    float4 c1zm, c0zm;
    if (zv > 0) { c1zm = curr[I(1,x,y,zv-1,d)]; c0zm = curr[I(0,x,y,zv-1,d)]; }
    else {       // z-1 of lane k is lane k-1 of the last vector; lane 0 has no z-1
        const float4 a = curr[I(1,x,y,d.nv-1,d)]; c1zm = float4(0.0f, a.x, a.y, a.z);
        const float4 b = curr[I(0,x,y,d.nv-1,d)]; c0zm = float4(0.0f, b.x, b.y, b.z);
    }
    const float4 c2ym = curr[I(2,x,ym,zv,d)], c2xm = curr[I(2,xm,y,zv,d)];
    const float4 c1xm = curr[I(1,xm,y,zv,d)], c0ym = curr[I(0,x,ym,zv,d)];
    float4 v;
    v = volt[I(0,x,y,zv,d)]; v = v * vv[0*d.numOps+op]; v = FMA(vi[0*d.numOps+op], ((c2 - c2ym) - c1) + c1zm, v); volt[I(0,x,y,zv,d)] = v;
    v = volt[I(1,x,y,zv,d)]; v = v * vv[1*d.numOps+op]; v = FMA(vi[1*d.numOps+op], ((c0 - c0zm) - c2) + c2xm, v); volt[I(1,x,y,zv,d)] = v;
    v = volt[I(2,x,y,zv,d)]; v = v * vv[2*d.numOps+op]; v = FMA(vi[2*d.numOps+op], ((c1 - c1xm) - c0) + c0ym, v); volt[I(2,x,y,zv,d)] = v;
}

kernel void updateI(device float4* curr [[buffer(0)]], device const float4* volt [[buffer(1)]],
                    device const float4* ii [[buffer(2)]], device const float4* iv [[buffer(3)]],
                    device const uint* opi [[buffer(4)]], constant Dims& d [[buffer(5)]],
                    uint3 t [[thread_position_in_grid]])
{
    const uint zv = t.x, y = t.y, x = t.z;
    if (zv >= d.nv || y+1 >= d.ny || x+1 >= d.nx) return;   // UpdateCurrents(0, numLines[0]-1), y < ny-1
    const uint op = opi[(x*d.ny + y)*d.nv + zv];
    const float4 v0 = volt[I(0,x,y,zv,d)], v1 = volt[I(1,x,y,zv,d)], v2 = volt[I(2,x,y,zv,d)];
    float4 v1zp, v0zp;
    if (zv+1 < d.nv) { v1zp = volt[I(1,x,y,zv+1,d)]; v0zp = volt[I(0,x,y,zv+1,d)]; }
    else {             // z+1 of lane k is lane k+1 of vector 0; the last lane has none
        const float4 a = volt[I(1,x,y,0,d)]; v1zp = float4(a.y, a.z, a.w, 0.0f);
        const float4 b = volt[I(0,x,y,0,d)]; v0zp = float4(b.y, b.z, b.w, 0.0f);
    }
    const float4 v2yp = volt[I(2,x,y+1,zv,d)], v0yp = volt[I(0,x,y+1,zv,d)];
    const float4 v2xp = volt[I(2,x+1,y,zv,d)], v1xp = volt[I(1,x+1,y,zv,d)];
    float4 c;
    c = curr[I(0,x,y,zv,d)]; c = c * ii[0*d.numOps+op]; c = FMA(iv[0*d.numOps+op], ((v2 - v2yp) - v1) + v1zp, c); curr[I(0,x,y,zv,d)] = c;
    c = curr[I(1,x,y,zv,d)]; c = c * ii[1*d.numOps+op]; c = FMA(iv[1*d.numOps+op], ((v0 - v0zp) - v2) + v2xp, c); curr[I(1,x,y,zv,d)] = c;
    c = curr[I(2,x,y,zv,d)]; c = c * ii[2*d.numOps+op]; c = FMA(iv[2*d.numOps+op], ((v1 - v1xp) - v0) + v0yp, c); curr[I(2,x,y,zv,d)] = c;
}

// ---- diamond-blocked sweep (--diamond K), 2026-11-04 ----
// Schedule after luikore's Metal engine (openEMS pull request #228, macos/doc/metal-engine.rst, GPL): each of x and
// y is split into mountain ranges, which shrink by one cell per half-step (E: the low edge, H: the high edge), and
// valley ranges between them, which grow into what the mountains left; the four products (MM, MV, VM, VV) are four
// dispatches in that order, and one threadgroup advances one tile over K timesteps in place, z complete, with a
// threadgroup barrier between half-steps. Every cell sees the operands of the unblocked kernels in the same order,
// so the fields are bit-identical to them. The per-cell arithmetic below is copied from updateV / updateI.
struct Phase { uint depth, ts0, xtype, ytype, period0; };   // type 0 = mountain, 1 = valley; period0: 0 = no period
struct ExcB { uint count, length, period; };

inline void cellV(device float4* volt, device const float4* curr, device const float4* vv, device const float4* vi,
                  device const uint* opi, constant Dims& d, uint x, uint y, uint zv)
{
    const uint op = opi[(x*d.ny + y)*d.nv + zv];
    const uint xm = x > 0 ? x-1 : x, ym = y > 0 ? y-1 : y;
    const float4 c0 = curr[I(0,x,y,zv,d)], c1 = curr[I(1,x,y,zv,d)], c2 = curr[I(2,x,y,zv,d)];
    float4 c1zm, c0zm;
    if (zv > 0) { c1zm = curr[I(1,x,y,zv-1,d)]; c0zm = curr[I(0,x,y,zv-1,d)]; }
    else {
        const float4 a = curr[I(1,x,y,d.nv-1,d)]; c1zm = float4(0.0f, a.x, a.y, a.z);
        const float4 b = curr[I(0,x,y,d.nv-1,d)]; c0zm = float4(0.0f, b.x, b.y, b.z);
    }
    const float4 c2ym = curr[I(2,x,ym,zv,d)], c2xm = curr[I(2,xm,y,zv,d)];
    const float4 c1xm = curr[I(1,xm,y,zv,d)], c0ym = curr[I(0,x,ym,zv,d)];
    float4 v;
    v = volt[I(0,x,y,zv,d)]; v = v * vv[0*d.numOps+op]; v = FMA(vi[0*d.numOps+op], ((c2 - c2ym) - c1) + c1zm, v); volt[I(0,x,y,zv,d)] = v;
    v = volt[I(1,x,y,zv,d)]; v = v * vv[1*d.numOps+op]; v = FMA(vi[1*d.numOps+op], ((c0 - c0zm) - c2) + c2xm, v); volt[I(1,x,y,zv,d)] = v;
    v = volt[I(2,x,y,zv,d)]; v = v * vv[2*d.numOps+op]; v = FMA(vi[2*d.numOps+op], ((c1 - c1xm) - c0) + c0ym, v); volt[I(2,x,y,zv,d)] = v;
}

inline void cellI(device float4* curr, device const float4* volt, device const float4* ii, device const float4* iv,
                  device const uint* opi, constant Dims& d, uint x, uint y, uint zv)
{
    const uint op = opi[(x*d.ny + y)*d.nv + zv];
    const float4 v0 = volt[I(0,x,y,zv,d)], v1 = volt[I(1,x,y,zv,d)], v2 = volt[I(2,x,y,zv,d)];
    float4 v1zp, v0zp;
    if (zv+1 < d.nv) { v1zp = volt[I(1,x,y,zv+1,d)]; v0zp = volt[I(0,x,y,zv+1,d)]; }
    else {
        const float4 a = volt[I(1,x,y,0,d)]; v1zp = float4(a.y, a.z, a.w, 0.0f);
        const float4 b = volt[I(0,x,y,0,d)]; v0zp = float4(b.y, b.z, b.w, 0.0f);
    }
    const float4 v2yp = volt[I(2,x,y+1,zv,d)], v0yp = volt[I(0,x,y+1,zv,d)];
    const float4 v2xp = volt[I(2,x+1,y,zv,d)], v1xp = volt[I(1,x+1,y,zv,d)];
    float4 c;
    c = curr[I(0,x,y,zv,d)]; c = c * ii[0*d.numOps+op]; c = FMA(iv[0*d.numOps+op], ((v2 - v2yp) - v1) + v1zp, c); curr[I(0,x,y,zv,d)] = c;
    c = curr[I(1,x,y,zv,d)]; c = c * ii[1*d.numOps+op]; c = FMA(iv[1*d.numOps+op], ((v0 - v0zp) - v2) + v2xp, c); curr[I(1,x,y,zv,d)] = c;
    c = curr[I(2,x,y,zv,d)]; c = c * ii[2*d.numOps+op]; c = FMA(iv[2*d.numOps+op], ((v1 - v1xp) - v0) + v0yp, c); curr[I(2,x,y,zv,d)] = c;
}

// The range of a tile at half-step s: a mountain [lo, hi) is [lo + s/2, hi - (s+1)/2), a valley between two
// mountains (lo = the left mountain's hi, hi = the right mountain's lo) is [lo - (s+1)/2, hi + s/2); clipped to [0, n).
inline int2 span(int2 r, uint type, uint s, int n)
{
    const int fl = int(s / 2), ce = int((s + 1) / 2);
    int a = type == 0 ? r.x + fl : r.x - ce, b = type == 0 ? r.y - ce : r.y + fl;
    return int2(max(a, 0), min(b, n));
}

kernel void diamond(device float4* volt [[buffer(0)]], device float4* curr [[buffer(1)]],
                    device const float4* vv [[buffer(2)]], device const float4* vi [[buffer(3)]],
                    device const float4* ii [[buffer(4)]], device const float4* iv [[buffer(5)]],
                    device const uint* opi [[buffer(6)]], constant Dims& d [[buffer(7)]],
                    device const int2* xr [[buffer(8)]], device const int2* yr [[buffer(9)]],
                    constant Phase& p [[buffer(10)]],
                    device const uint* eidx [[buffer(11)]], device const uint* edir [[buffer(12)]],
                    device const uint* edel [[buffer(13)]], device const float* eamp [[buffer(14)]],
                    device const float* esig [[buffer(15)]], constant ExcB& e [[buffer(16)]],
                    uint3 tg [[threadgroup_position_in_grid]], uint tid [[thread_index_in_threadgroup]],
                    uint3 tptg [[threads_per_threadgroup]])
{
    const uint tgs = tptg.x;
    const int2 rx = xr[tg.x], ry = yr[tg.y];
    for (uint s = 0; s < 2 * p.depth; ++s)
    {
        const int2 sx = span(rx, p.xtype, s, int(d.nx)), sy = span(ry, p.ytype, s, int(d.ny));
        const int wx = sx.y - sx.x, wy = sy.y - sy.x;
        if (wx > 0 && wy > 0)
        {
            const uint count = uint(wx) * uint(wy) * d.nv;
            for (uint i = tid; i < count; i += tgs)
            {
                const uint zv = i % d.nv, r = i / d.nv;
                const uint y = uint(sy.x) + r % uint(wy), x = uint(sx.x) + r / uint(wy);
                if ((s & 1) == 0) cellV(volt, curr, vv, vi, opi, d, x, y, zv);
                else if (x + 1 < d.nx && y + 1 < d.ny) cellI(curr, volt, ii, iv, opi, d, x, y, zv);
            }
        }
        threadgroup_barrier(mem_flags::mem_device);
        if ((s & 1) == 0 && e.count > 0)
        {
            // the excitation of this step for the cells this tile updated, in entry order (one thread, as excite)
            if (tid == 0 && wx > 0 && wy > 0)
            {
                const uint ts = p.ts0 + s / 2, period = p.period0 ? p.period0 : ts + 1;
                for (uint k = 0; k < e.count; ++k)
                {
                    const int x = int(eidx[k]), y = int(eidx[e.count+k]);
                    if (x < sx.x || x >= sx.y || y < sy.x || y >= sy.y) continue;
                    int pos = int(ts) - int(edel[k]);
                    pos *= (pos > 0);
                    pos %= int(period);
                    pos *= (pos < int(e.length));
                    const uint z = eidx[2*e.count+k];
                    const uint zv = z % d.nv, lane = z / d.nv;
                    device float* f = (device float*)&volt[I(edir[k],uint(x),uint(y),zv,d)];
                    f[lane] = FMA(eamp[k], esig[pos], f[lane]);
                }
            }
            threadgroup_barrier(mem_flags::mem_device);
        }
    }
}

kernel void excite(device float4* volt [[buffer(0)]], device const uint* idx [[buffer(1)]],
                   device const uint* dir [[buffer(2)]], device const uint* delay [[buffer(3)]],
                   device const float* amp [[buffer(4)]], device const float* sig [[buffer(5)]],
                   constant Dims& d [[buffer(6)]], constant ExcP& e [[buffer(7)]],
                   uint tid [[thread_position_in_grid]])
{
    // one thread applies all entries in order, exactly as the CPU loop does (entries may share a cell)
    if (tid != 0) return;
    for (uint k = 0; k < e.count; ++k)
    {
        int pos = int(e.numTS) - int(delay[k]);
        pos *= (pos > 0);
        pos %= int(e.period);
        pos *= (pos < int(e.length));
        const uint x = idx[k], y = idx[e.count+k], z = idx[2*e.count+k];
        const uint zv = z % d.nv, lane = z / d.nv;
        device float* f = (device float*)&volt[I(dir[k],x,y,zv,d)];
        f[lane] = FMA(amp[k], sig[pos], f[lane]);
    }
}
"""

struct Dims { var nx: UInt32; var ny: UInt32; var nv: UInt32; var numOps: UInt32 }
struct ExcP { var count: UInt32; var length: UInt32; var numTS: UInt32; var period: UInt32 }

func fail(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }

var args = Array(CommandLine.arguments.dropFirst())
var batch = 50
var dump = true
if let i = args.firstIndex(of: "--batch") { batch = Int(args[i+1])!; args.removeSubrange(i...i+1) }
if let i = args.firstIndex(of: "--nodump") { dump = false; args.remove(at: i) }
var nofma = false
if let i = args.firstIndex(of: "--nofma") { nofma = true; args.remove(at: i) }
var diamondK = 0, tileM = 0, tileV = 0, tgThreads = 0
if let i = args.firstIndex(of: "--diamond") { diamondK = Int(args[i+1])!; args.removeSubrange(i...i+1) }
if let i = args.firstIndex(of: "--tile") {
    let p = args[i+1].split(separator: ",").map { Int($0)! }; tileM = p[0]; tileV = p[1]; args.removeSubrange(i...i+1)
}
if let i = args.firstIndex(of: "--tg") { tgThreads = Int(args[i+1])!; args.removeSubrange(i...i+1) }
guard args.count >= 3, let nrts = Int(args[1]) else {
    fail("usage: fdtd_swift OP_DIR NRTS OUT_DIR [--batch N] [--nodump] [--nofma] [--diamond K [--tile M,V] [--tg T]]")
}
let opDir = args[0], outDir = args[2]

func readJSON(_ path: String) -> [String: Any] {
    guard let d = FileManager.default.contents(atPath: path),
          let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { fail("cannot read \(path)") }
    return j
}
let h = readJSON(opDir + "/header.json")
let nl = (h["numLines"] as! [Int]).map { UInt32($0) }
let nv = UInt32(h["numVectors"] as! Int), numOps = UInt32(h["numOps"] as! Int)
let voltCount = h["voltCount"] as! Int, sigLen = h["signalLength"] as! Int
let signalPeriod = h["signalPeriod"] as! Double, dT = h["dT"] as! Double
let exts = h["extensions"] as! [String]
if exts.contains(where: { $0 != "Excitation Extension" }) { fail("unsupported extensions: \(exts)") }
if (h["currCount"] as? Int ?? 0) > 0 { fail("current excitations are not implemented (currCount \(h["currCount"]!))") }
if voltCount == 0 { fail("the export has no voltage excitation: the fields would stay zero") }
let nx = nl[0], ny = nl[1], nz = nl[2]
let cells = Double(nx) * Double(ny) * Double(nz)

guard let dev = MTLCreateSystemDefaultDevice(), let queue = dev.makeCommandQueue() else { fail("no Metal device") }
func load(_ name: String) -> MTLBuffer {
    guard let d = FileManager.default.contents(atPath: opDir + "/" + name) else { fail("missing \(name)") }
    let n = max(d.count, 16)     // at least 16 bytes: Metal makes no zero-length buffer
    guard let b = dev.makeBuffer(length: n, options: .storageModeShared) else { fail("cannot allocate \(name)") }
    memset(b.contents(), 0, n)
    d.withUnsafeBytes { src in if d.count > 0 { b.contents().copyMemory(from: src.baseAddress!, byteCount: d.count) } }
    return b
}
let opi = load("op_index.u32"), vv = load("vv.f32"), vi = load("vi.f32"), ii = load("ii.f32"), iv = load("iv.f32")
let excIdx = load("exc_index.u32"), excDir = load("exc_dir.u32"), excDelay = load("exc_delay.u32"), excAmp = load("exc_amp.f32")
let sig = load("exc_signal.f32")
let nField = Int(3 * nx * ny * nv)
let volt = dev.makeBuffer(length: nField * 16, options: .storageModeShared)!
let curr = dev.makeBuffer(length: nField * 16, options: .storageModeShared)!
memset(volt.contents(), 0, nField * 16); memset(curr.contents(), 0, nField * 16)

let opts = MTLCompileOptions()
if #available(macOS 15, *) { opts.mathMode = .safe } else { opts.fastMathEnabled = false }
let lib: MTLLibrary
if nofma { opts.preprocessorMacros = ["NOFMA": 1 as NSNumber] }
do { lib = try dev.makeLibrary(source: msl, options: opts) } catch { fail("MSL compile: \(error)") }
func pipe(_ n: String) -> MTLComputePipelineState { try! dev.makeComputePipelineState(function: lib.makeFunction(name: n)!) }
let pV = pipe("updateV"), pI = pipe("updateI"), pE = pipe("excite")

var dims = Dims(nx: nx, ny: ny, nv: nv, numOps: numOps)
let w = pV.threadExecutionWidth
let tg = MTLSize(width: min(Int(nv), w), height: max(1, min(8, pV.maxTotalThreadsPerThreadgroup / min(Int(nv), w))), depth: 1)
let gridV = MTLSize(width: Int(nv), height: Int(ny), depth: Int(nx))
let gridI = MTLSize(width: Int(nv), height: Int(ny) - 1, depth: Int(nx) - 1)
let periodTS: UInt32? = signalPeriod > 0 ? UInt32(signalPeriod / dT) : nil

// Diamond tiles along one axis of n cells: mountains [m*P, m*P + M) and the valleys between them (P = M + V), every
// tile whose range at some half-step of a K-step block meets [0, n). M >= 2K - 1 keeps a mountain from inverting.
func tiles(_ n: Int, _ M: Int, _ V: Int, _ K: Int) -> (mountains: [Int32], valleys: [Int32]) {
    let P = M + V
    var mt = [Int32](), vl = [Int32]()
    for m in -1...(n / P + 1) {
        let a = m * P
        if a < n && a + M > 0 { mt += [Int32(a), Int32(a + M)] }
        let lo = a + M, hi = a + P                     // valley between mountain m and m + 1
        if lo - K < n && hi + K - 1 > 0 { vl += [Int32(lo), Int32(hi)] }
    }
    return (mt, vl)
}
let periodDia: UInt32 = periodTS ?? 0
struct PhaseH { var depth: UInt32; var ts0: UInt32; var xtype: UInt32; var ytype: UInt32; var period0: UInt32 }
struct ExcBH { var count: UInt32; var length: UInt32; var period: UInt32 }
var dTiles: [(MTLBuffer, Int)] = []
var pD: MTLComputePipelineState? = nil
var tgD = 0
if diamondK > 0 {
    if tileM == 0 { tileM = 2 * diamondK; tileV = 2 * diamondK }
    if tileM < 2 * diamondK - 1 { fail("--tile: the mountain width must be at least 2K-1 = \(2 * diamondK - 1)") }
    pD = pipe("diamond")
    tgD = tgThreads > 0 ? min(tgThreads, pD!.maxTotalThreadsPerThreadgroup) : pD!.maxTotalThreadsPerThreadgroup
    let tx = tiles(Int(nx), tileM, tileV, diamondK), ty = tiles(Int(ny), tileM, tileV, diamondK)
    for t in [tx.mountains, tx.valleys, ty.mountains, ty.valleys] {
        dTiles.append((dev.makeBuffer(bytes: t, length: max(t.count, 4) * 4, options: .storageModeShared)!, t.count / 2))
    }
}

let t0 = Date()
var ts = 0
if diamondK > 0 {
    var excb = ExcBH(count: UInt32(voltCount), length: UInt32(sigLen), period: 0)
    while ts < nrts {
        let cb = queue.makeCommandBuffer()!
        let enc = cb.makeComputeCommandEncoder()!
        var inCB = 0
        while ts < nrts && inCB < batch {
            let depth = min(diamondK, nrts - ts)
            for (xt, yt) in [(0, 0), (0, 1), (1, 0), (1, 1)] {     // MM, MV, VM, VV
                let (xb, nxT) = dTiles[xt], (yb, nyT) = dTiles[2 + yt]
                if nxT == 0 || nyT == 0 { continue }
                var ph = PhaseH(depth: UInt32(depth), ts0: UInt32(ts), xtype: UInt32(xt), ytype: UInt32(yt), period0: periodDia)
                enc.setComputePipelineState(pD!)
                enc.setBuffer(volt, offset: 0, index: 0); enc.setBuffer(curr, offset: 0, index: 1)
                enc.setBuffer(vv, offset: 0, index: 2); enc.setBuffer(vi, offset: 0, index: 3)
                enc.setBuffer(ii, offset: 0, index: 4); enc.setBuffer(iv, offset: 0, index: 5)
                enc.setBuffer(opi, offset: 0, index: 6); enc.setBytes(&dims, length: 16, index: 7)
                enc.setBuffer(xb, offset: 0, index: 8); enc.setBuffer(yb, offset: 0, index: 9)
                enc.setBytes(&ph, length: MemoryLayout<PhaseH>.stride, index: 10)
                enc.setBuffer(excIdx, offset: 0, index: 11); enc.setBuffer(excDir, offset: 0, index: 12)
                enc.setBuffer(excDelay, offset: 0, index: 13); enc.setBuffer(excAmp, offset: 0, index: 14)
                enc.setBuffer(sig, offset: 0, index: 15); enc.setBytes(&excb, length: MemoryLayout<ExcBH>.stride, index: 16)
                enc.dispatchThreadgroups(MTLSize(width: nxT, height: nyT, depth: 1),
                                         threadsPerThreadgroup: MTLSize(width: tgD, height: 1, depth: 1))
            }
            ts += depth; inCB += depth
        }
        enc.endEncoding()
        cb.commit()
        if ts >= nrts { cb.waitUntilCompleted() }
    }
}
while ts < nrts {
    let cb = queue.makeCommandBuffer()!
    let enc = cb.makeComputeCommandEncoder()!
    for _ in 0..<min(batch, nrts - ts) {
        enc.setComputePipelineState(pV)
        enc.setBuffer(volt, offset: 0, index: 0); enc.setBuffer(curr, offset: 0, index: 1)
        enc.setBuffer(vv, offset: 0, index: 2); enc.setBuffer(vi, offset: 0, index: 3)
        enc.setBuffer(opi, offset: 0, index: 4); enc.setBytes(&dims, length: 16, index: 5)
        enc.dispatchThreads(gridV, threadsPerThreadgroup: tg)
        if voltCount > 0 {
            var e = ExcP(count: UInt32(voltCount), length: UInt32(sigLen), numTS: UInt32(ts), period: periodTS ?? UInt32(ts + 1))
            enc.setComputePipelineState(pE)
            enc.setBuffer(volt, offset: 0, index: 0); enc.setBuffer(excIdx, offset: 0, index: 1)
            enc.setBuffer(excDir, offset: 0, index: 2); enc.setBuffer(excDelay, offset: 0, index: 3)
            enc.setBuffer(excAmp, offset: 0, index: 4); enc.setBuffer(sig, offset: 0, index: 5)
            enc.setBytes(&dims, length: 16, index: 6); enc.setBytes(&e, length: 16, index: 7)
            enc.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        }
        enc.setComputePipelineState(pI)
        enc.setBuffer(curr, offset: 0, index: 0); enc.setBuffer(volt, offset: 0, index: 1)
        enc.setBuffer(ii, offset: 0, index: 2); enc.setBuffer(iv, offset: 0, index: 3)
        enc.setBuffer(opi, offset: 0, index: 4); enc.setBytes(&dims, length: 16, index: 5)
        enc.dispatchThreads(gridI, threadsPerThreadgroup: tg)
        ts += 1
    }
    enc.endEncoding()
    cb.commit()
    if ts >= nrts { cb.waitUntilCompleted() }
}
let dt = Date().timeIntervalSince(t0)
let mode = diamondK > 0 ? String(format: "diamond K=%d tile %d,%d tg %d", diamondK, tileM, tileV, tgD) : "unblocked"
print(String(format: "Swift/Metal: %d timesteps, %.0f cells: %.3f s, %.1f MCells/s (batch %d, %@)", nrts, cells, dt, cells * Double(nrts) / dt / 1e6, batch, mode))

if dump {
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    let n3 = Int(3 * nx * ny * nz)
    var vOut = [Float](repeating: 0, count: n3), cOut = [Float](repeating: 0, count: n3)
    let vp = volt.contents().bindMemory(to: Float.self, capacity: nField * 4)
    let cp = curr.contents().bindMemory(to: Float.self, capacity: nField * 4)
    for n in 0..<3 { for x in 0..<Int(nx) { for y in 0..<Int(ny) { for z in 0..<Int(nz) {
        let zv = z % Int(nv), lane = z / Int(nv)
        let src = (((n * Int(nx) + x) * Int(ny) + y) * Int(nv) + zv) * 4 + lane
        let dst = ((n * Int(nx) + x) * Int(ny) + y) * Int(nz) + z
        vOut[dst] = vp[src]; cOut[dst] = cp[src]
    } } } }
    vOut.withUnsafeBytes { try! Data($0).write(to: URL(fileURLWithPath: outDir + "/volt.f32")) }
    cOut.withUnsafeBytes { try! Data($0).write(to: URL(fileURLWithPath: outDir + "/curr.f32")) }
    let js = "{\n \"numLines\": [\(nx), \(ny), \(nz)],\n \"numTS\": \(nrts),\n \"layout\": \"volt.f32 / curr.f32 [3][x][y][z] float32\"\n}\n"
    try! js.write(toFile: outDir + "/fields.json", atomically: true, encoding: .utf8)
}
