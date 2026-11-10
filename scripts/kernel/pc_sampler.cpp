// pc_sampler.cpp: which loop of kb_idx.cpp runs, by sampling the program counter (macOS, 2026-11-03).
// Build kb_idx.cpp with -Dmain=kb_main and link it with this file; the program then runs kb_main(argc, argv) in a
// worker thread while the main thread suspends every other thread of the process about every 100 us, reads its
// program counter (thread_get_state, allowed for the process's own threads) and resumes it. At the end it prints one
// line per sampled address (link-time address, i.e. minus the executable's slide) and its count, for loop_insns.py.
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <unistd.h>
#include <atomic>
#include <cstdio>
#include <map>
#include <thread>

int kb_main(int argc, char** argv);

int main(int argc, char** argv)
{
    std::atomic<bool> done{false};
    std::thread worker([&] { kb_main(argc, argv); done = true; });
    const mach_port_t me = mach_thread_self();
    const intptr_t slide = _dyld_get_image_vmaddr_slide(0);
    std::map<unsigned long long, long> hist;
    while (!done)
    {
        thread_act_array_t th;
        mach_msg_type_number_t n;
        if (task_threads(mach_task_self(), &th, &n) == KERN_SUCCESS)
        {
            for (mach_msg_type_number_t i = 0; i < n; ++i)
            {
                if (th[i] != me && thread_suspend(th[i]) == KERN_SUCCESS)
                {
                    arm_thread_state64_t st;
                    mach_msg_type_number_t cnt = ARM_THREAD_STATE64_COUNT;
                    if (thread_get_state(th[i], ARM_THREAD_STATE64, (thread_state_t)&st, &cnt) == KERN_SUCCESS)
                        ++hist[(unsigned long long)(arm_thread_state64_get_pc(st) - slide)];
                    thread_resume(th[i]);
                }
                mach_port_deallocate(mach_task_self(), th[i]);
            }
            vm_deallocate(mach_task_self(), (vm_address_t)th, n * sizeof(thread_act_t));
        }
        usleep(100);
    }
    worker.join();
    for (const auto& [pc, c] : hist)
        std::fprintf(stderr, "PC %llx %ld\n", pc, c);
    return 0;
}
