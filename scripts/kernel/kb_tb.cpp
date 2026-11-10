// kb_tb.cpp -- openEMS Engine_SSE_Compressed inner loops, standalone: temporal-blocking upper bound
//   (one independent sub-grid per thread, k=1 fused sweep versus k=2 two timesteps per sweep).
//
// The *_stock functions are the non-SSE2 path of Engine_SSE_Compressed::UpdateVoltages / UpdateCurrents of
// openEMS v0.37.0 (FDTD/engine_sse_compressed.cpp), with their comments removed:
//   Copyright (C) 2010 Thorsten Liebig (Thorsten.Liebig@gmx.de)
// Modified for emsKit, 2026-10-28: the *_clean variants and the temporal-blocking driver added.
//
// This program is free software: you can redistribute it and/or modify it under the terms of the GNU General
// Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
// implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
// for more details. You should have received a copy of the GNU General Public License along with this program
// (LICENSE in emsKit); if not, see <https://www.gnu.org/licenses/>.
//
//   clang++ -std=c++17 -O3 -DNDEBUG kb_tb.cpp -o kb_tb && ./kb_tb [steps [Nx Ny Nz]]
//   steps is rounded up to an even count (k=2 does two per sweep); Nx >= 80 (8 x-lines per sub-grid at 10
//   threads), Ny >= 16, Nz >= 13.
// Same data layout as openEMS (ArrayENG I-J-K-N: f4vector[x][y][zvec][3], 4 z-cells per
// f4vector, uint32 operator index per f4vector, 12 coefficient tables of f4vector).
// The Engine struct is the one of kb_idx.cpp; main runs only its *_clean loops (same arithmetic in the same
// order as the stock copy, invariants hoisted), each thread on its own sub-grid with no barrier, and compares
// the k=2 fields with the k=1 fields of the first sub-grid.
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

    // ------- from openEMS v0.37.0 engine_sse_compressed.cpp (non-SSE2 path), comments removed -------
    __attribute__((noinline)) void UpdateVoltages_stock(unsigned int startX, unsigned int numX)
    {
        f4vector* f4_volt = f4_volt_ptr->data();
        f4vector* f4_curr = f4_curr_ptr->data();
        unsigned int pos[3];
        unsigned int v_pos;
        unsigned int i_pos;
        unsigned i_pos_z_start, i_pos_z_end;
        int i_shift[3];
        f4vector temp;
        int v_N_shift  = f4_volt_ptr->stride(0);
        int i_N_shift  = f4_curr_ptr->stride(0);
        i_shift[2] = f4_curr_ptr->stride(3);
        pos[0] = startX;
        unsigned int index=0;
        for (unsigned int posX=0; posX<numX; ++posX)
        {
            i_shift[0] = (pos[0]>0)*f4_curr_ptr->stride(1);
            for (pos[1]=0; pos[1]<numLines[1]; ++pos[1])
            {
                i_shift[1] = (pos[1]>0)*f4_curr_ptr->stride(2);
                for (pos[2]=1; pos[2]<numVectors; ++pos[2])
                {
                    index = Op->m_Op_index(pos[0], pos[1], pos[2]);
                    i_pos = f4_curr_ptr->linearIndex({0, pos[0], pos[1], pos[2]});
                    v_pos = f4_volt_ptr->linearIndex({0, pos[0], pos[1], pos[2]});
                    f4_volt[v_pos].v *= Op->f4_vv_Compressed[0][index].v;
                    f4_volt[v_pos].v += Op->f4_vi_Compressed[0][index].v * (
                        f4_curr[i_pos + 2*i_N_shift             ].v -
                        f4_curr[i_pos + 2*i_N_shift - i_shift[1]].v -
                        f4_curr[i_pos +   i_N_shift             ].v +
                        f4_curr[i_pos +   i_N_shift - i_shift[2]].v );
                    v_pos += v_N_shift;
                    f4_volt[v_pos].v *= Op->f4_vv_Compressed[1][index].v;
                    f4_volt[v_pos].v += Op->f4_vi_Compressed[1][index].v * (
                        f4_curr[i_pos                           ].v -
                        f4_curr[i_pos               - i_shift[2]].v -
                        f4_curr[i_pos + 2*i_N_shift             ].v +
                        f4_curr[i_pos + 2*i_N_shift - i_shift[0]].v );
                    v_pos += v_N_shift;
                    f4_volt[v_pos].v *= Op->f4_vv_Compressed[2][index].v;
                    f4_volt[v_pos].v += Op->f4_vi_Compressed[2][index].v * (
                        f4_curr[i_pos + i_N_shift             ].v -
                        f4_curr[i_pos + i_N_shift - i_shift[0]].v -
                        f4_curr[i_pos                         ].v +
                        f4_curr[i_pos             - i_shift[1]].v );
                }
                i_pos_z_start = f4_curr_ptr->linearIndex({0, pos[0], pos[1], 0});
                i_pos_z_end   = f4_curr_ptr->linearIndex({0, pos[0], pos[1], numVectors-1});
                index = Op->m_Op_index(pos[0], pos[1], 0);
                temp.f[0] = 0;
                temp.f[1] = f4_curr[i_pos_z_end + i_N_shift].f[0];
                temp.f[2] = f4_curr[i_pos_z_end + i_N_shift].f[1];
                temp.f[3] = f4_curr[i_pos_z_end + i_N_shift].f[2];
                v_pos = f4_volt_ptr->linearIndex({0, pos[0], pos[1], 0});
                f4_volt[v_pos].v *= Op->f4_vv_Compressed[0][index].v;
                f4_volt[v_pos].v += Op->f4_vi_Compressed[0][index].v * (
                    f4_curr[i_pos_z_start + i_N_shift*2             ].v -
                    f4_curr[i_pos_z_start + i_N_shift*2 - i_shift[1]].v -
                    f4_curr[i_pos_z_start + i_N_shift  ].v +
                    temp.v );
                temp.f[0] = 0;
                temp.f[1] = f4_curr[i_pos_z_end].f[0];
                temp.f[2] = f4_curr[i_pos_z_end].f[1];
                temp.f[3] = f4_curr[i_pos_z_end].f[2];
                v_pos += v_N_shift;
                f4_volt[v_pos].v *= Op->f4_vv_Compressed[1][index].v;
                f4_volt[v_pos].v += Op->f4_vi_Compressed[1][index].v * (
                    f4_curr[i_pos_z_start].v -
                    temp.v -
                    f4_curr[i_pos_z_start + i_N_shift*2             ].v +
                    f4_curr[i_pos_z_start + i_N_shift*2 - i_shift[0]].v );
                v_pos += v_N_shift;
                f4_volt[v_pos].v *= Op->f4_vv_Compressed[2][index].v;
                f4_volt[v_pos].v += Op->f4_vi_Compressed[2][index].v * (
                    f4_curr[i_pos_z_start + i_N_shift             ].v -
                    f4_curr[i_pos_z_start + i_N_shift - i_shift[0]].v -
                    f4_curr[i_pos_z_start                         ].v +
                    f4_curr[i_pos_z_start             - i_shift[1]].v );
            }
            ++pos[0];
        }
    }

    __attribute__((noinline)) void UpdateCurrents_stock(unsigned int startX, unsigned int numX)
    {
        f4vector* f4_volt = f4_volt_ptr->data();
        f4vector* f4_curr = f4_curr_ptr->data();
        unsigned int v_pos;
        unsigned int i_pos;
        int v_shift[3];
        unsigned v_pos_z_start, v_pos_z_end;
        unsigned int pos[3];
        f4vector temp;
        int v_N_shift  = f4_volt_ptr->stride(0);
        int i_N_shift  = f4_curr_ptr->stride(0);
        for (unsigned int n=0;n<3;++n)
            v_shift[n]= f4_volt_ptr->stride(n+1);
        pos[0] = startX;
        unsigned int index;
        for (unsigned int posX=0; posX<numX; ++posX)
        {
            for (pos[1]=0; pos[1]<numLines[1]-1; ++pos[1])
            {
                for (pos[2]=0; pos[2]<numVectors-1; ++pos[2])
                {
                    index = Op->m_Op_index(pos[0], pos[1], pos[2]);
                    i_pos = f4_curr_ptr->linearIndex({0, pos[0], pos[1], pos[2]});
                    v_pos = f4_volt_ptr->linearIndex({0, pos[0], pos[1], pos[2]});
                    f4_curr[i_pos].v *= Op->f4_ii_Compressed[0][index].v;
                    f4_curr[i_pos].v += Op->f4_iv_Compressed[0][index].v * (
                        f4_volt[v_pos + 2*v_N_shift             ].v -
                        f4_volt[v_pos + 2*v_N_shift + v_shift[1]].v -
                        f4_volt[v_pos +   v_N_shift             ].v +
                        f4_volt[v_pos +   v_N_shift + v_shift[2]].v );
                    i_pos += i_N_shift;
                    f4_curr[i_pos].v *= Op->f4_ii_Compressed[1][index].v;
                    f4_curr[i_pos].v += Op->f4_iv_Compressed[1][index].v * (
                        f4_volt[v_pos                           ].v -
                        f4_volt[v_pos +               v_shift[2]].v -
                        f4_volt[v_pos + 2*v_N_shift             ].v +
                        f4_volt[v_pos + 2*v_N_shift + v_shift[0]].v );
                    i_pos += i_N_shift;
                    f4_curr[i_pos].v *= Op->f4_ii_Compressed[2][index].v;
                    f4_curr[i_pos].v += Op->f4_iv_Compressed[2][index].v * (
                        f4_volt[v_pos +   v_N_shift             ].v -
                        f4_volt[v_pos +   v_N_shift + v_shift[0]].v -
                        f4_volt[v_pos                           ].v +
                        f4_volt[v_pos +               v_shift[1]].v );
                }
                v_pos_z_start = f4_volt_ptr->linearIndex({0, pos[0], pos[1], 0});
                v_pos_z_end   = f4_volt_ptr->linearIndex({0, pos[0], pos[1], numVectors-1});
                index = Op->m_Op_index(pos[0], pos[1], numVectors-1);
                temp.f[0] = f4_volt[v_pos_z_start + v_N_shift].f[1];
                temp.f[1] = f4_volt[v_pos_z_start + v_N_shift].f[2];
                temp.f[2] = f4_volt[v_pos_z_start + v_N_shift].f[3];
                temp.f[3] = 0;
                i_pos = f4_curr_ptr->linearIndex({0, pos[0], pos[1], numVectors-1});
                f4_curr[i_pos].v *= Op->f4_ii_Compressed[0][index].v;
                f4_curr[i_pos].v += Op->f4_iv_Compressed[0][index].v * (
                    f4_volt[v_pos_z_end + 2*v_N_shift             ].v -
                    f4_volt[v_pos_z_end + 2*v_N_shift + v_shift[1]].v -
                    f4_volt[v_pos_z_end + v_N_shift               ].v +
                    temp.v );
                temp.f[0] = f4_volt[v_pos_z_start].f[1];
                temp.f[1] = f4_volt[v_pos_z_start].f[2];
                temp.f[2] = f4_volt[v_pos_z_start].f[3];
                temp.f[3] = 0;
                i_pos += i_N_shift;
                f4_curr[i_pos].v *= Op->f4_ii_Compressed[1][index].v;
                f4_curr[i_pos].v += Op->f4_iv_Compressed[1][index].v * (
                    f4_volt[v_pos_z_end].v -
                    temp.v -
                    f4_volt[v_pos_z_end + 2*v_N_shift             ].v +
                    f4_volt[v_pos_z_end + 2*v_N_shift + v_shift[0]].v );
                i_pos += i_N_shift;
                f4_curr[i_pos].v *= Op->f4_ii_Compressed[2][index].v;
                f4_curr[i_pos].v += Op->f4_iv_Compressed[2][index].v * (
                    f4_volt[v_pos_z_end + v_N_shift             ].v -
                    f4_volt[v_pos_z_end + v_N_shift + v_shift[0]].v -
                    f4_volt[v_pos_z_end                         ].v +
                    f4_volt[v_pos_z_end             + v_shift[1]].v );
            }
            ++pos[0];
        }
    }

    // ---------------- clean: same arithmetic, same order; invariants hoisted ----------------
    static inline v4sf shl1(v4sf a) { // {0, a0, a1, a2}  (what the scalar temp.f[] code does)
        const v4sf z = {0,0,0,0};
        return __builtin_shufflevector(z, a, 0, 4, 5, 6);
    }
    static inline v4sf shr1(v4sf a) { // {a1, a2, a3, 0}
        const v4sf z = {0,0,0,0};
        return __builtin_shufflevector(a, z, 1, 2, 3, 4);
    }

    __attribute__((noinline)) void UpdateVoltages_clean(unsigned int startX, unsigned int numX)
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
            for (uint32_t y = 0; y < ny; ++y)
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

    __attribute__((noinline)) void UpdateCurrents_clean(unsigned int startX, unsigned int numX)
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
            for (uint32_t y = 0; y + 1 < ny; ++y)
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

// ------------------------------------------------------------------ harness
struct CondBarrier {
    std::mutex m; std::condition_variable cv; unsigned count, gen, n;
    explicit CondBarrier(unsigned n_) : count(n_), gen(0), n(n_) {}
    void wait() {
        std::unique_lock<std::mutex> l(m); unsigned g = gen;
        if (--count == 0) { gen++; count = n; l.unlock(); cv.notify_all(); return; }
        while (g == gen) cv.wait(l);
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


// Upper bound for temporal blocking: every thread sweeps its own independent grid (no halo exchange,
// no extensions); k=1 = fused sweep (V(x), I(x-1)), k=2 = two timesteps per sweep (V(x), I(x-1), V'(x-2), I'(x-3)).
int main(int argc, char** argv) {
    int steps = argc > 1 ? atoi(argv[1]) : 20;
    steps += steps % 2;                                  // k=2 runs two timesteps per sweep
    const uint32_t Nx = argc > 2 ? atoi(argv[2]) : 209, Ny = argc > 3 ? atoi(argv[3]) : 209, Nz = argc > 4 ? atoi(argv[4]) : 180;
    if (Nx < 80 || Ny < 16 || Nz < 13) {   // the field blob needs 8 x-lines per sub-grid at 10 threads, 16 y, 4 z-vectors
        fprintf(stderr, "kb_tb: the grid must be at least 80 x 16 x 13 (Nx Ny Nz)\n");
        return 1;
    }
    const uint32_t nvec = (Nz + 3) / 4, nops = 7600;
    printf("grid %ux%ux%u split into one independent sub-grid per thread, %d steps\n", Nx, Ny, Nz, steps);
    for (unsigned T : {1u, 4u, 6u, 8u, 10u}) {
        const uint32_t nx = Nx / T;
        const size_t nf4 = (size_t)nx * Ny * nvec * 3;
        Operator op;
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
        std::vector<ArrENG> volt(T), curr(T);
        std::vector<Engine> eng(T);
        for (unsigned g = 0; g < T; ++g) {
            for (ArrENG* a : {&volt[g], &curr[g]}) {
                a->m_extent[0] = 3; a->m_extent[1] = nx; a->m_extent[2] = Ny; a->m_extent[3] = nvec;
                a->m_stride[0] = 1; a->m_stride[1] = Ny*nvec*3; a->m_stride[2] = nvec*3; a->m_stride[3] = 3;
                a->m_ptr = alloc_f4(nf4);
            }
            eng[g].numLines[0] = nx; eng[g].numLines[1] = Ny; eng[g].numLines[2] = Nz; eng[g].numVectors = nvec;
            eng[g].f4_volt_ptr = &volt[g]; eng[g].f4_curr_ptr = &curr[g]; eng[g].Op = &op;
        }
        auto reset = [&]() {
            for (unsigned g = 0; g < T; ++g) {
                memset(volt[g].m_ptr, 0, nf4 * 16); memset(curr[g].m_ptr, 0, nf4 * 16);
                for (uint32_t x = nx/2-4; x < nx/2+4; ++x) for (uint32_t y = Ny/2-8; y < Ny/2+8; ++y) for (uint32_t z = nvec/2-2; z < nvec/2+2; ++z)
                    for (int n = 0; n < 3; ++n) for (int l = 0; l < 4; ++l)
                        volt[g].m_ptr[volt[g].linearIndex({(uint32_t)n,x,y,z})].f[l] = 0.1f * (1 + n) * (1 + l) * ((x+y+z) % 5);
            }
        };
        auto sweep1 = [&](Engine& e) {
            for (uint32_t x = 0; x < nx + 1; ++x) {
                if (x < nx) e.UpdateVoltages_clean(x, 1);
                if (x >= 1 && x-1 < nx-1) e.UpdateCurrents_clean(x-1, 1);
            }
        };
        auto sweep2 = [&](Engine& e) {
            for (uint32_t x = 0; x < nx + 3; ++x) {
                if (x < nx) e.UpdateVoltages_clean(x, 1);
                if (x >= 1 && x-1 < nx-1) e.UpdateCurrents_clean(x-1, 1);
                if (x >= 2 && x-2 < nx) e.UpdateVoltages_clean(x-2, 1);
                if (x >= 3 && x-3 < nx-1) e.UpdateCurrents_clean(x-3, 1);
            }
        };
        auto run = [&](int k) -> double {
            reset();
            std::vector<std::thread> th;
            auto t0 = std::chrono::steady_clock::now();
            for (unsigned t = 0; t < T; ++t) th.emplace_back([&, t]() {
                for (int s = 0; s < steps; s += k) { if (k == 1) sweep1(eng[t]); else sweep2(eng[t]); }
            });
            for (auto& t : th) t.join();
            double sec = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
            return T * (double)nx * Ny * Nz * steps / sec / 1e6;
        };
        double r1 = run(1);
        std::vector<f4vector> vref(volt[0].m_ptr, volt[0].m_ptr + nf4), cref(curr[0].m_ptr, curr[0].m_ptr + nf4);
        double r2 = run(2);
        bool same = !memcmp(vref.data(), volt[0].m_ptr, nf4*16) && !memcmp(cref.data(), curr[0].m_ptr, nf4*16);
        printf("%2u threads (sub-grid %ux%ux%u): k=1 %6.0f MC/s (%3.0f GB/s at 49 B)   k=2 %6.0f MC/s  ratio %.2f  %s\n",
               T, nx, Ny, Nz, r1, r1*49/1e3, r2, r2/r1, same ? "bit-identical" : "MISMATCH");
        for (unsigned g = 0; g < T; ++g) { free(volt[g].m_ptr); free(curr[g].m_ptr); }
        free(op.m_Op_index.m_ptr);
    }
    return 0;
}
