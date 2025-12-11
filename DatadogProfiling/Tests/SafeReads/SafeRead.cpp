/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "mach_sampling_profiler.h"
#include "ctor_profiler.h"

#ifdef __APPLE__

#include <dlfcn.h>
#include <thread>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <signal.h>
#include <setjmp.h>
#include <mach/thread_act.h>
#include <mach/thread_status.h>
#include <mach/machine/thread_state.h>
#include <mach-o/loader.h>
#include <mach-o/dyld.h>

// Safe memory read using signal handling
// Thread-local storage for signal-based safe memory reading
static thread_local sigjmp_buf g_safe_read_handler;
static thread_local volatile sig_atomic_t g_is_safe_read = false;

// Previous signal handlers to restore if needed
static struct sigaction g_prev_sigbus_handler;
static struct sigaction g_prev_sigsegv_handler;

/**
 * Signal handler for catching memory access errors during stack unwinding.
 * If safe_read is active, longjmp back to the safe point.
 * Otherwise, call the previous handler or use default behavior.
 */
static void safe_read_signal_handler(int sig, siginfo_t* info, void* context) {
    // If we're in a safe_read, recover via longjmp
    if (g_is_safe_read) {
        siglongjmp(g_safe_read_handler, 1);
    }

    // Not in safe_read - forward to previous handler
    struct sigaction* prev = (sig == SIGBUS) ? &g_prev_sigbus_handler : &g_prev_sigsegv_handler;

    if (prev->sa_flags & SA_SIGINFO) {
        if (prev->sa_sigaction) {
            prev->sa_sigaction(sig, info, context);
        }
    } else if (prev->sa_handler == SIG_DFL) {
        // Restore default handler using sigaction (async-signal-safe)
        struct sigaction dfl = {};
        dfl.sa_handler = SIG_DFL;
        sigemptyset(&dfl.sa_mask);
        sigaction(sig, &dfl, nullptr);
        raise(sig);
    } else if (prev->sa_handler != SIG_IGN) {
        prev->sa_handler(sig);
    }
}

extern "C" {

void init_main_thread_id_and_safe_read_handlers(void) {

    struct sigaction sa = {};
    sa.sa_sigaction = safe_read_signal_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_SIGINFO;

    // Install handlers and save previous ones
    sigaction(SIGBUS, &sa, &g_prev_sigbus_handler);
    sigaction(SIGSEGV, &sa, &g_prev_sigsegv_handler);
}

/**
 * Safely reads memory from a potentially invalid address.
 * Uses signal handling to validate memory access.
 * If memory is invalid, SIGBUS/SIGSEGV is caught and we return false.
 *
 * This logic is optimized and inlined in Production in the stack_trace_sample_thread function.
 */
bool safe_read_memory(void* addr, void* buffer, size_t size) {
    g_is_safe_read = true;

    if (sigsetjmp(g_safe_read_handler, 1) == 0) {
        // try direct memory copy
        memcpy(buffer, addr, size);
        g_is_safe_read = false;
        return true;
    }

    // Memory access failed
    g_is_safe_read = false;
    return false;
}

} // extern "C"
#endif // __APPLE__

extern "C" void* get_invalid_address(void) {
    return (void*)0xDEADBEEF;
}
