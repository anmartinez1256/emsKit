// kb_tile.cpp -- openEMS Engine_SSE_Compressed inner loops, standalone: temporal blocking with ONE tile for all threads
//   (the schedule of upstream master's cpu engine, FDTD/engine_plan.cpp: trapezoids along x, all threads on one
//   tile, the tile split along y, a spin barrier after every half step), against the fused k=1 sweep on one
//   independent sub-grid per thread (kb_tb.cpp's baseline).
//
// The update loops are the *_clean loops of kb_tb.cpp with a y range; they follow the non-SSE2 path of
// Engine_SSE_Compressed::UpdateVoltages / UpdateCurrents of openEMS v0.37.0 (FDTD/engine_sse_compressed.cpp):
//   Copyright (C) 2010 Thorsten Liebig (Thorsten.Liebig@gmx.de)
// Modified for emsKit, 2026-11-11: the y ranges and the shared-tile driver.
//
// This program is free software: you can redistribute it and/or modify it under the terms of the GNU General
// Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
// implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
// for more details. You should have received a copy of the GNU General Public License along with this program
// (LICENSE in emsKit); if not, see <https://www.gnu.org/licenses/>.
//
//   clang++ -std=c++17 -O3 -DNDEBUG kb_tile.cpp -o kb_tile && ./kb_tile [steps [Nx Ny Nz]]
//   KB_THREADS=a,b,c: the thread counts (default 4,8,10).
// A block of k steps on a tile [a, b) of x-lines: the core runs E_t on [a+t, b-t) and H_t on [a+t, b-t-1) for
// t = 0 .. k-1 (no shrinking at a domain edge), then the wedge at every tile boundary c runs E_t on [c-t, c+t) and
// H_t on [c-t-1, c+t). Each of these ranges is one task: every thread does its y rows of it, then all meet at a
// barrier. The fields after the run are compared with a plain sweep (E everywhere, H everywhere) of one thread.
// steps should be a multiple of 840 / gcd so that every k in the list divides it (the default 56 serves k = 1, 2, 4, 7, 8).
#include <initializer_list>
#include <array>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <thread>
#include <vector>

typedef float v4sf __attribute__((vector_size(16)));
union f4vector { v4sf v; float f[4]; };

struct ArrENG {            // mirrors ArrayLib::ArrayENG<f4vector> (I-J-K-N strides)
    uint32_t m_extent[4] = {0,0,0,0}, m_stride[4] = {0,0,0,0};
    f4vector* __restrict m_ptr = nullptr;
    uint32_t stride(uint32_t n) const { return m_stride[n]; }
    uint32_t linearIndex(std::array<uint32_t,4> t) const {
        return m_stride[0]*t[0] + m_stride[1]*t[1] + m_stride[2]*t[2] + m_stride[3]*t[3];
    }
    f4vector* data() const { return m_ptr; }
};
struct ArrIJK {            // mirrors ArrayLib::ArrayIJK<unsigned int>
    uint32_t m_extent[3] = {0,0,0}, m_stride[3] = {0,0,0};
    uint32_t* __restrict m_ptr = nullptr;
    uint32_t& operator()(uint32_t i, uint32_t j, uint32_t k) const {
        return m_ptr[m_stride[0]*i + m_stride[1]*j + m_stride[2]*k];
    }
};
struct Operator {
    ArrIJK m_Op_index;
    std::vector<f4vector> f4_vv_Compressed[3], f4_vi_Compressed[3], f4_iv_Compressed[3], f4_ii_Compressed[3];
};

struct Engine {
    uint32_t numLines[3];
    uint32_t numVectors;
    ArrENG* f4_volt_ptr;
    ArrENG* f4_curr_ptr;
    const Operator* Op;

    static inline v4sf shl1(v4sf a) { // {0, a0, a1, a2}  (what the scalar temp.f[] code does)
        const v4sf z = {0,0,0,0};
        return __builtin_shufflevector(z, a, 0, 4, 5, 6);
    }
    static inline v4sf shr1(v4sf a) { // {a1, a2, a3, 0}
        const v4sf z = {0,0,0,0};
        return __builtin_shufflevector(a, z, 1, 2, 3, 4);
    }

    __attribute__((noinline)) void UpdateVoltagesY(unsigned int startX, unsigned int numX, uint32_t y0, uint32_t y1)
    {
        f4vector* __restrict volt = f4_volt_ptr->data();
        const f4vector* __restrict curr = f4_curr_ptr->data();
        const uint32_t* __restrict idx = Op->m_Op_index.m_ptr;
        const f4vector* __restrict vv0 = Op->f4_vv_Compressed[0].data();
        const f4vector* __restrict vv1 = Op->f4_vv_Compressed[1].data();
        const f4vector* __restrict vv2 = Op->f4_vv_Compressed[2].data();
        const f4vector* __restrict vi0 = Op->f4_vi_Compressed[0].data();
        const f4vector* __restrict vi1 = Op->f4_vi_Compressed[1].data();
        const f4vector* __restrict vi2 = Op->f4_vi_Compressed[2].data();
        const ptrdiff_t sx = f4_curr_ptr->stride(1), sy = f4_curr_ptr->stride(2);
        const ptrdiff_t isx = Op->m_Op_index.m_stride[0], isy = Op->m_Op_index.m_stride[1];
        const uint32_t ny = numLines[1], nvec = numVectors;
        for (uint32_t x = startX; x < startX + numX; ++x)
        {
            const ptrdiff_t shx = (x > 0) ? sx : 0;
            for (uint32_t y = y0; y < y1 && y < ny; ++y)
            {
                const ptrdiff_t shy = (y > 0) ? sy : 0;
                f4vector* __restrict v = volt + x*sx + y*sy;
                const f4vector* __restrict c = curr + x*sx + y*sy;
                const uint32_t* __restrict ip = idx + x*isx + y*isy;
                for (uint32_t z = 1; z < nvec; ++z)
                {
                    const uint32_t i = ip[z];
                    f4vector* __restrict vz = v + 3*z;
                    const f4vector* __restrict cz = c + 3*z;
                    v4sf a, t;
                    t = cz[2].v - cz[2-shy].v - cz[1].v + cz[1-3].v;
                    a = vz[0].v * vv0[i].v;  vz[0].v = a + vi0[i].v * t;
                    t = cz[0].v - cz[0-3].v - cz[2].v + cz[2-shx].v;
                    a = vz[1].v * vv1[i].v;  vz[1].v = a + vi1[i].v * t;
                    t = cz[1].v - cz[1-shx].v - cz[0].v + cz[0-shy].v;
                    a = vz[2].v * vv2[i].v;  vz[2].v = a + vi2[i].v * t;
                }
                { // z-vector 0: lanes shift in from the last vector of the line
                    const uint32_t i = ip[0];
                    const f4vector* __restrict ce = c + 3*(nvec-1);
                    v4sf a, t;
                    t = c[2].v - c[2-shy].v - c[1].v + shl1(ce[1].v);
                    a = v[0].v * vv0[i].v;  v[0].v = a + vi0[i].v * t;
                    t = c[0].v - shl1(ce[0].v) - c[2].v + c[2-shx].v;
                    a = v[1].v * vv1[i].v;  v[1].v = a + vi1[i].v * t;
                    t = c[1].v - c[1-shx].v - c[0].v + c[0-shy].v;
                    a = v[2].v * vv2[i].v;  v[2].v = a + vi2[i].v * t;
                }
            }
        }
    }

    __attribute__((noinline)) void UpdateCurrentsY(unsigned int startX, unsigned int numX, uint32_t y0, uint32_t y1)
    {
        const f4vector* __restrict volt = f4_volt_ptr->data();
        f4vector* __restrict curr = f4_curr_ptr->data();
        const uint32_t* __restrict idx = Op->m_Op_index.m_ptr;
        const f4vector* __restrict ii0 = Op->f4_ii_Compressed[0].data();
        const f4vector* __restrict ii1 = Op->f4_ii_Compressed[1].data();
        const f4vector* __restrict ii2 = Op->f4_ii_Compressed[2].data();
        const f4vector* __restrict iv0 = Op->f4_iv_Compressed[0].data();
        const f4vector* __restrict iv1 = Op->f4_iv_Compressed[1].data();
        const f4vector* __restrict iv2 = Op->f4_iv_Compressed[2].data();
        const ptrdiff_t sx = f4_volt_ptr->stride(1), sy = f4_volt_ptr->stride(2);
        const ptrdiff_t isx = Op->m_Op_index.m_stride[0], isy = Op->m_Op_index.m_stride[1];
        const uint32_t ny = numLines[1], nvec = numVectors;
        for (uint32_t x = startX; x < startX + numX; ++x)
        {
            for (uint32_t y = y0; y < y1 && y + 1 < ny; ++y)
            {
                const f4vector* __restrict v = volt + x*sx + y*sy;
                f4vector* __restrict c = curr + x*sx + y*sy;
                const uint32_t* __restrict ip = idx + x*isx + y*isy;
                for (uint32_t z = 0; z + 1 < nvec; ++z)
                {
                    const uint32_t i = ip[z];
                    const f4vector* __restrict vz = v + 3*z;
                    f4vector* __restrict cz = c + 3*z;
                    v4sf a, t;
                    t = vz[2].v - vz[2+sy].v - vz[1].v + vz[1+3].v;
                    a = cz[0].v * ii0[i].v;  cz[0].v = a + iv0[i].v * t;
                    t = vz[0].v - vz[0+3].v - vz[2].v + vz[2+sx].v;
                    a = cz[1].v * ii1[i].v;  cz[1].v = a + iv1[i].v * t;
                    t = vz[1].v - vz[1+sx].v - vz[0].v + vz[0+sy].v;
                    a = cz[2].v * ii2[i].v;  cz[2].v = a + iv2[i].v * t;
                }
                { // last z-vector
                    const uint32_t i = ip[nvec-1];
                    const f4vector* __restrict ve = v + 3*(nvec-1);
                    f4vector* __restrict ce = c + 3*(nvec-1);
                    v4sf a, t;
                    t = ve[2].v - ve[2+sy].v - ve[1].v + shr1(v[1].v);
                    a = ce[0].v * ii0[i].v;  ce[0].v = a + iv0[i].v * t;
                    t = ve[0].v - shr1(v[0].v) - ve[2].v + ve[2+sx].v;
                    a = ce[1].v * ii1[i].v;  ce[1].v = a + iv1[i].v * t;
                    t = ve[1].v - ve[1+sx].v - ve[0].v + ve[0+sy].v;
                    a = ce[2].v * ii2[i].v;  ce[2].v = a + iv2[i].v * t;
                }
            }
        }
    }
};

static inline void cpu_relax() {   // the spin-wait hint of the CPU (arm64 as measured; x86 builds too)
#if defined(__aarch64__) || defined(__arm64__)
    __asm__ volatile("yield");
#elif defined(__x86_64__) || defined(__i386__)
    __builtin_ia32_pause();
#else
    std::this_thread::yield();
#endif
}
struct SpinBarrier {
    alignas(128) std::atomic<unsigned> count{0};
    alignas(128) std::atomic<unsigned> gen{0};
    unsigned n;
    explicit SpinBarrier(unsigned n_) : n(n_) {}
    void wait() {
        unsigned g = gen.load(std::memory_order_acquire);
        if (count.fetch_add(1, std::memory_order_acq_rel) + 1 == n) { count.store(0); gen.store(g+1, std::memory_order_release); }
        else while (gen.load(std::memory_order_acquire) == g) cpu_relax();
    }
};

static f4vector* alloc_f4(size_t n) {
    void* p = nullptr;
    if (posix_memalign(&p, 64, n * sizeof(f4vector))) abort();
    memset(p, 0, n * sizeof(f4vector));
    return (f4vector*)p;
}



struct Task { bool e; uint32_t x0, x1; };

// KB_THREADS=a,b,c: the thread counts of the multi-thread runs (the defaults suit an Apple M5: 4 P + 6 E cores).
static std::vector<unsigned> kbThreads(std::initializer_list<unsigned> def) {
    std::vector<unsigned> v;
    for (const char* p = getenv("KB_THREADS"); p && *p; ) {
        char* q; unsigned long t = strtoul(p, &q, 10);
        if (q == p) break;
        if (t >= 1 && t <= 256) v.push_back((unsigned)t);
        p = (*q == ',') ? q + 1 : q + strlen(q);
    }
    if (v.empty()) v.assign(def.begin(), def.end());
    return v;
}

int main(int argc, char** argv) {
    int steps = argc > 1 ? atoi(argv[1]) : 56;
    const uint32_t Nx = argc > 2 ? atoi(argv[2]) : 209, Ny = argc > 3 ? atoi(argv[3]) : 209, Nz = argc > 4 ? atoi(argv[4]) : 180;
    if (Nx < 80 || Ny < 16 || Nz < 13) { fprintf(stderr, "kb_tile: the grid must be at least 80 x 16 x 13 (Nx Ny Nz)\n"); return 1; }
    const uint32_t nvec = (Nz + 3) / 4, nops = 7600;
    const double lineMB = (double)Ny * nvec * 4 * 24 / 1048576;   // V and I of one x-line
    printf("grid %ux%ux%u = %.2f M cells, %.2f MB of fields per x-line, %d steps\n", Nx, Ny, Nz, 1e-6*Nx*Ny*Nz, lineMB, steps);

    auto makeOp = [&](Operator& op, uint32_t nx) {
        op.m_Op_index.m_extent[0] = nx; op.m_Op_index.m_extent[1] = Ny; op.m_Op_index.m_extent[2] = nvec;
        op.m_Op_index.m_stride[0] = Ny*nvec; op.m_Op_index.m_stride[1] = nvec; op.m_Op_index.m_stride[2] = 1;
        op.m_Op_index.m_ptr = (uint32_t*)malloc((size_t)nx*Ny*nvec*4);
        for (uint32_t x = 0; x < nx; ++x) for (uint32_t y = 0; y < Ny; ++y) for (uint32_t z = 0; z < nvec; ++z)
            op.m_Op_index(x,y,z) = (x/4*131u + y/4*17u + z*3u) % nops;
        for (int n = 0; n < 3; ++n) {
            op.f4_vv_Compressed[n].resize(nops); op.f4_vi_Compressed[n].resize(nops);
            op.f4_ii_Compressed[n].resize(nops); op.f4_iv_Compressed[n].resize(nops);
            for (uint32_t k = 0; k < nops; ++k) for (int l = 0; l < 4; ++l) {
                float eps = 1.0f + (k % 7) * 0.5f;
                op.f4_vv_Compressed[n][k].f[l] = 1.0f - 1e-4f * (k % 3);
                op.f4_vi_Compressed[n][k].f[l] = 0.5f / eps;
                op.f4_ii_Compressed[n][k].f[l] = 1.0f;
                op.f4_iv_Compressed[n][k].f[l] = 0.5f;
            }
        }
    };
    auto makeGrid = [&](ArrENG& volt, ArrENG& curr, Engine& e, const Operator& op, uint32_t nx) {
        for (ArrENG* a : {&volt, &curr}) {
            a->m_extent[0] = 3; a->m_extent[1] = nx; a->m_extent[2] = Ny; a->m_extent[3] = nvec;
            a->m_stride[0] = 1; a->m_stride[1] = Ny*nvec*3; a->m_stride[2] = nvec*3; a->m_stride[3] = 3;
            a->m_ptr = alloc_f4((size_t)nx * Ny * nvec * 3);
        }
        e.numLines[0] = nx; e.numLines[1] = Ny; e.numLines[2] = Nz; e.numVectors = nvec;
        e.f4_volt_ptr = &volt; e.f4_curr_ptr = &curr; e.Op = &op;
    };
    auto fill = [&](ArrENG& volt, ArrENG& curr, uint32_t nx) {
        const size_t nf4 = (size_t)nx * Ny * nvec * 3;
        memset(volt.m_ptr, 0, nf4 * 16); memset(curr.m_ptr, 0, nf4 * 16);
        for (uint32_t x = nx/2-4; x < nx/2+4; ++x) for (uint32_t y = Ny/2-8; y < Ny/2+8; ++y) for (uint32_t z = nvec/2-2; z < nvec/2+2; ++z)
            for (int n = 0; n < 3; ++n) for (int l = 0; l < 4; ++l)
                volt.m_ptr[volt.linearIndex({(uint32_t)n,x,y,z})].f[l] = 0.1f * (1 + n) * (1 + l) * ((x+y+z) % 5);
    };

    // the whole grid: reference fields from a plain sweep of one thread
    Operator op; makeOp(op, Nx);
    ArrENG volt, curr; Engine eng; makeGrid(volt, curr, eng, op, Nx);
    const size_t nf4 = (size_t)Nx * Ny * nvec * 3;
    fill(volt, curr, Nx);
    for (int s = 0; s < steps; ++s) { eng.UpdateVoltagesY(0, Nx, 0, Ny); eng.UpdateCurrentsY(0, Nx-1, 0, Ny); }
    std::vector<f4vector> vref(volt.m_ptr, volt.m_ptr + nf4), cref(curr.m_ptr, curr.m_ptr + nf4);

    for (unsigned T : kbThreads({4u, 8u, 10u})) {
        // baseline: the fused k=1 sweep, one independent sub-grid per thread (as kb_tb.cpp)
        double base = 0;
        {
            const uint32_t nx = Nx / T;
            Operator bop; makeOp(bop, nx);
            std::vector<ArrENG> bv(T), bc(T); std::vector<Engine> be(T);
            for (unsigned g = 0; g < T; ++g) { makeGrid(bv[g], bc[g], be[g], bop, nx); fill(bv[g], bc[g], nx); }
            std::vector<std::thread> th;
            auto t0 = std::chrono::steady_clock::now();
            for (unsigned t = 0; t < T; ++t) th.emplace_back([&, t]() {
                for (int s = 0; s < steps; ++s)
                    for (uint32_t x = 0; x < nx + 1; ++x) {
                        if (x < nx) be[t].UpdateVoltagesY(x, 1, 0, Ny);
                        if (x >= 1 && x-1 < nx-1) be[t].UpdateCurrentsY(x-1, 1, 0, Ny);
                    }
            });
            for (auto& t : th) t.join();
            const double sec = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
            base = T * (double)nx * Ny * Nz * steps / sec / 1e6;
            for (unsigned g = 0; g < T; ++g) { free(bv[g].m_ptr); free(bc[g].m_ptr); }
            free(bop.m_Op_index.m_ptr);
        }
        printf("%2u threads: fused k=1 on %u sub-grids %6.0f MC/s (%3.0f GB/s at 49 B)\n", T, T, base, base*49/1e3);

        for (auto kw : std::vector<std::array<uint32_t,2>>{{1,4},{2,5},{2,15},{4,9},{4,15},{7,15},{8,17},{7,30}}) {
            const uint32_t k = kw[0], W = kw[1];
            if (steps % (int)k) continue;
            // the tasks of one block
            std::vector<Task> tasks;
            std::vector<uint32_t> edge;   // tile boundaries 0 = edge[0] < .. < edge.back() = Nx
            for (uint32_t x = 0; x < Nx; x += W) edge.push_back(x);
            if (Nx - edge.back() < 2*k && edge.size() > 1) edge.pop_back();   // the last tile takes a short rest
            edge.push_back(Nx);
            for (size_t j = 0; j + 1 < edge.size(); ++j) {
                const uint32_t a = edge[j], b = edge[j+1];
                for (uint32_t t = 0; t < k; ++t) {
                    const uint32_t lo = (a == 0) ? 0 : a + t, hiE = (b == Nx) ? Nx : b - t, hiH = (b == Nx) ? Nx - 1 : b - t - 1;
                    if (hiE > lo) tasks.push_back({true, lo, hiE});
                    if (hiH > lo) tasks.push_back({false, lo, hiH});
                }
            }
            for (size_t j = 1; j + 1 < edge.size(); ++j) {
                const uint32_t c = edge[j];
                for (uint32_t t = 0; t < k; ++t) {
                    if (t > 0) tasks.push_back({true, c - t, c + t});
                    tasks.push_back({false, c - t - 1, c + t});
                }
            }
            fill(volt, curr, Nx);
            SpinBarrier bar(T);
            std::vector<std::thread> th;
            auto t0 = std::chrono::steady_clock::now();
            for (unsigned t = 0; t < T; ++t) th.emplace_back([&, t]() {
                const uint32_t y0 = (uint32_t)((uint64_t)Ny * t / T), y1 = (uint32_t)((uint64_t)Ny * (t + 1) / T);
                for (int s = 0; s < steps; s += k)
                    for (const Task& q : tasks) {
                        if (q.e) eng.UpdateVoltagesY(q.x0, q.x1 - q.x0, y0, y1);
                        else eng.UpdateCurrentsY(q.x0, q.x1 - q.x0, y0, y1);
                        bar.wait();
                    }
            });
            for (auto& t : th) t.join();
            const double sec = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
            const double rate = (double)Nx * Ny * Nz * steps / sec / 1e6;
            const bool same = !memcmp(vref.data(), volt.m_ptr, nf4*16) && !memcmp(cref.data(), curr.m_ptr, nf4*16);
            printf("   one tile for all, k=%u W=%2u (%4.1f MB, %zu barriers per step): %6.0f MC/s  x%.2f of fused  %s\n",
                   k, W, W*lineMB, tasks.size()/k, rate, rate/base, same ? "bit-identical" : "MISMATCH");
        }
    }
    free(volt.m_ptr); free(curr.m_ptr); free(op.m_Op_index.m_ptr);
    return 0;
}
