// kb_idx.cpp -- openEMS Engine_SSE_Compressed inner loops, standalone.
//
// The *_stock functions are the non-SSE2 path of Engine_SSE_Compressed::UpdateVoltages / UpdateCurrents of
// openEMS v0.37.0 (FDTD/engine_sse_compressed.cpp), with their comments removed:
//   Copyright (C) 2010 Thorsten Liebig (Thorsten.Liebig@gmx.de)
// Modified for emsKit, 2026-10-28: the *_clean variants, the threading and the benchmark driver added.
//
// This program is free software: you can redistribute it and/or modify it under the terms of the GNU General
// Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
// implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
// for more details. You should have received a copy of the GNU General Public License along with this program
// (LICENSE in emsKit); if not, see <https://www.gnu.org/licenses/>.
//
//   clang++ -std=c++17 -O3 -DNDEBUG kb_idx.cpp -o kb_idx && ./kb_idx [steps [Nx Ny Nz [extra_barriers]]]
//   knobs: KB_NOPS (unique operators, default 4000), KB_RANDOM=1 (random operator indices), KB_PAD=bytes (offset the
//   current array: the placement test of ../cache_valley), KB_FUSED=1 (fused E/H sweep), KB_ONE=1 (only the two one-thread runs,
//   then a hash of the final fields, to compare builds with different compilers).
// Same data layout as openEMS (ArrayENG I-J-K-N: f4vector[x][y][zvec][3], 4 z-cells per
// f4vector, uint32 operator index per f4vector, 12 coefficient tables of f4vector).
// "stock" = the copy of FDTD/engine_sse_compressed.cpp described above, with the same member
// indirections (this->Op->vector[...] and ArrayIJK strides), "clean" = same arithmetic in
// the same order (bit-identical) with invariants hoisted and pointer walking.
// Threading: static x-slab split + mutex/condvar barrier (what engine_multithread.cpp does)
// versus dynamic x-chunks (atomic counter) + spin barrier.
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
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

int main(int argc, char** argv) {
    const int steps = argc > 1 ? atoi(argv[1]) : 8;
    const uint32_t Nx = argc > 2 ? atoi(argv[2]) : 209, Ny = argc > 3 ? atoi(argv[3]) : 209, Nz = argc > 4 ? atoi(argv[4]) : 180; // default: patch x5
    const int extra_barriers = argc > 5 ? atoi(argv[5]) : 0;  // extra barrier waits per timestep (openEMS: 2 + 6*N_ext)
    if (Nx < 20 || Ny < 16 || Nz < 13) {   // 2 x-lines per thread at 10 threads; the field blob needs 16 x 16 x 4 z-vectors
        fprintf(stderr, "kb_idx: the grid must be at least 20 x 16 x 13 (Nx Ny Nz)\n");
        return 1;
    }
    const uint32_t nvec = (Nz + 3) / 4;
    const uint32_t nops = getenv("KB_NOPS") ? atoi(getenv("KB_NOPS")) : 4000; const int kb_random = getenv("KB_RANDOM") ? atoi(getenv("KB_RANDOM")) : 0;                              // unique operators (patch x5 has ~7.6k)
    const size_t nf4 = (size_t)Nx * Ny * nvec * 3;
    printf("grid %ux%ux%u (%.3f Mcells, numVectors=%u), %u operators, %d steps, %d extra barriers/TS, hw threads %u\n",
           Nx, Ny, Nz, Nx*Ny*(double)Nz/1e6, nvec, nops, steps, extra_barriers, std::thread::hardware_concurrency());

    ArrENG volt, curr;
    for (ArrENG* a : {&volt, &curr}) {
        a->m_extent[0] = 3; a->m_extent[1] = Nx; a->m_extent[2] = Ny; a->m_extent[3] = nvec;
        a->m_stride[0] = 1; a->m_stride[1] = Ny*nvec*3; a->m_stride[2] = nvec*3; a->m_stride[3] = 3;
        a->m_ptr = alloc_f4(nf4);
    }
    if (getenv("KB_PAD")) {   // offset the current array by KB_PAD bytes (placement test)
        size_t pad = atol(getenv("KB_PAD")) / 16;
        curr.m_ptr = alloc_f4(nf4 + pad) + pad;
    }
    printf("volt %p curr %p diff %ld KB\n", (void*)volt.m_ptr, (void*)curr.m_ptr, ((long)((char*)curr.m_ptr-(char*)volt.m_ptr))/1024);
    Operator op;
    op.m_Op_index.m_extent[0] = Nx; op.m_Op_index.m_extent[1] = Ny; op.m_Op_index.m_extent[2] = nvec;
    op.m_Op_index.m_stride[0] = Ny*nvec; op.m_Op_index.m_stride[1] = nvec; op.m_Op_index.m_stride[2] = 1;
    op.m_Op_index.m_ptr = (uint32_t*)malloc((size_t)Nx*Ny*nvec*4);
    for (uint32_t x = 0; x < Nx; ++x) for (uint32_t y = 0; y < Ny; ++y) for (uint32_t z = 0; z < nvec; ++z)
        op.m_Op_index(x,y,z) = kb_random ? (uint32_t)(((uint64_t)(x*2654435761u ^ (y*40503u) ^ (z*2246822519u)) * 0x9E3779B1u >> 7) % nops) : (x/4*131u + y/4*17u + z*3u) % nops;        // spatially coherent indices
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
    Engine eng;
    eng.numLines[0] = Nx; eng.numLines[1] = Ny; eng.numLines[2] = Nz; eng.numVectors = nvec;
    eng.f4_volt_ptr = &volt; eng.f4_curr_ptr = &curr; eng.Op = &op;

    auto reset = [&]() {
        memset(volt.m_ptr, 0, nf4 * 16); memset(curr.m_ptr, 0, nf4 * 16);
        // a blob of field in the middle so the arithmetic is on normal numbers
        for (uint32_t x = Nx/2-8; x < Nx/2+8; ++x) for (uint32_t y = Ny/2-8; y < Ny/2+8; ++y) for (uint32_t z = nvec/2-2; z < nvec/2+2; ++z)
            for (int n = 0; n < 3; ++n) for (int l = 0; l < 4; ++l)
                volt.m_ptr[volt.linearIndex({(uint32_t)n,x,y,z})].f[l] = 0.1f * (1 + n) * (1 + l) * ((x+y+z) % 5);
    };

    // run: variant 0 = stock, 1 = clean; sched 0 = static slabs + condvar, 1 = dynamic chunks + spin
    auto run = [&](int variant, unsigned nthreads, int sched) -> double {
        reset();
        std::vector<std::thread> th;
        CondBarrier cb(nthreads); SpinBarrier sb(nthreads);
        std::atomic<uint32_t> next{0};
        const uint32_t chunk = 2;
        auto body = [&](unsigned tid) {
            // static split like Operator_Multithread::CalcStartStopLines
            uint32_t per = Nx / nthreads, rem = Nx % nthreads;
            uint32_t start = tid * per + (tid < rem ? tid : rem), n = per + (tid < rem ? 1 : 0);
            uint32_t nh = (tid == nthreads-1) ? n - 1 : n;
            for (int s = 0; s < steps; ++s) {
                if (sched == 0) {
                    for (int b = 0; b < extra_barriers/2; ++b) cb.wait();
                    if (variant == 0) eng.UpdateVoltages_stock(start, n); else eng.UpdateVoltages_clean(start, n);
                    cb.wait();
                    for (int b = 0; b < extra_barriers - extra_barriers/2; ++b) cb.wait();
                    if (variant == 0) eng.UpdateCurrents_stock(start, nh); else eng.UpdateCurrents_clean(start, nh);
                    cb.wait();
                } else if (sched == 2) {
                    // fused sweep like Engine_Multithread::FusedTimestep: V(x), then I(x-1); I(start-1) after a barrier
                    for (uint32_t x = start; x < start+n; ++x) {
                        eng.UpdateVoltages_clean(x, 1);
                        if (x > start) eng.UpdateCurrents_clean(x-1, 1);
                    }
                    sb.wait();
                    if (start > 0) eng.UpdateCurrents_clean(start-1, 1);
                    sb.wait();
                } else {
                    for (int b = 0; b < extra_barriers; ++b) sb.wait();
                    for (;;) { uint32_t x0 = next.fetch_add(chunk); if (x0 >= Nx) break; uint32_t n0 = std::min(chunk, Nx - x0);
                        if (variant == 0) eng.UpdateVoltages_stock(x0, n0); else eng.UpdateVoltages_clean(x0, n0); }
                    sb.wait();
                    if (tid == 0) next.store(0);
                    sb.wait();
                    for (;;) { uint32_t x0 = next.fetch_add(chunk); if (x0 >= Nx-1) break; uint32_t n0 = std::min(chunk, Nx-1 - x0);
                        if (variant == 0) eng.UpdateCurrents_stock(x0, n0); else eng.UpdateCurrents_clean(x0, n0); }
                    sb.wait();
                    if (tid == 0) next.store(0);
                    sb.wait();
                }
            }
        };
        auto t0 = std::chrono::steady_clock::now();
        for (unsigned t = 0; t < nthreads; ++t) th.emplace_back(body, t);
        for (auto& t : th) t.join();
        double sec = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
        return Nx * Ny * (double)Nz * steps / sec / 1e6;
    };

    // reference result: stock, 1 thread
    double ref = run(0, 1, 0);
    std::vector<f4vector> vref(volt.m_ptr, volt.m_ptr + nf4), cref(curr.m_ptr, curr.m_ptr + nf4);
    auto check = [&]() {
        bool ok = !memcmp(vref.data(), volt.m_ptr, nf4*16) && !memcmp(cref.data(), curr.m_ptr, nf4*16);
        double mx = 0; for (size_t i = 0; i < nf4; ++i) for (int l = 0; l < 4; ++l) mx = std::max(mx, (double)std::abs(volt.m_ptr[i].f[l]));
        return ok ? std::string("bit-identical") : std::string("MISMATCH") + " (max|E|=" + std::to_string(mx) + ")";
    };
    printf("%-34s %8.0f MC/s   %s\n", "stock, 1 thread", ref, "reference");
    if (getenv("KB_FUSED")) {
        for (unsigned nt : {1u, 4u, 8u, 10u}) {
            char name[64];
            snprintf(name, sizeof name, "clean, %u thr dynamic+spin", nt); double d = run(1, nt, 1); printf("%-34s %8.0f MC/s   %s\n", name, d, check().c_str());
            snprintf(name, sizeof name, "fused, %u thr static+spin", nt); double f = run(1, nt, 2); printf("%-34s %8.0f MC/s   %s\n", name, f, check().c_str());
        }
        return 0;
    }
    double c1 = run(1, 1, 0); printf("%-34s %8.0f MC/s   %s\n", "clean, 1 thread", c1, check().c_str());
    if (getenv("KB_ONE")) {   // FNV-1a over the stock run's final voltages and currents
        uint64_t h = 1469598103934665603ull;
        for (const std::vector<f4vector>* v : {&vref, &cref}) {
            const unsigned char* p = (const unsigned char*)v->data();
            for (size_t i = 0; i < v->size() * sizeof(f4vector); ++i) h = (h ^ p[i]) * 1099511628211ull;
        }
        printf("final fields hash %016llx\n", (unsigned long long)h);
        return 0;
    }
    for (unsigned nt : {4u, 8u, 10u}) {
        char name[64];
        snprintf(name, sizeof name, "stock, %u thr static+condvar", nt); double a = run(0, nt, 0); printf("%-34s %8.0f MC/s   %s\n", name, a, check().c_str());
        snprintf(name, sizeof name, "clean, %u thr static+condvar", nt); double b = run(1, nt, 0); printf("%-34s %8.0f MC/s   %s\n", name, b, check().c_str());
        snprintf(name, sizeof name, "stock, %u thr dynamic+spin",   nt); double c = run(0, nt, 1); printf("%-34s %8.0f MC/s   %s\n", name, c, check().c_str());
        snprintf(name, sizeof name, "clean, %u thr dynamic+spin",   nt); double d = run(1, nt, 1); printf("%-34s %8.0f MC/s   %s\n", name, d, check().c_str());
    }
    return 0;
}
