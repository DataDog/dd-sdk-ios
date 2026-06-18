/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "memory_swizzle_poc.h"
#include "memory_profiler.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#include <atomic>
#include <objc/objc.h>
#include <objc/runtime.h>
#include <objc/message.h>

// =====================================================================
// +allocWithZone: Swizzling Spike (follow-up to RUM-16460)
//
// Strategy:
//   1. Resolve +[NSObject allocWithZone:] via the Obj-C runtime (no
//      @selector / no Obj-C source — runtime API is plain C).
//   2. Replace its IMP with our trampoline using method_setImplementation.
//      The previous IMP is stored so we can both forward and restore.
//   3. Each invocation: forward to the original, then (under the
//      enabled flag) report the new instance + class to the passive
//      sampler in memory_profiler.cpp.
//
// The trampoline writes through the same Poisson sampler / reentrancy
// guard / side-table as the zone-hook path: any allocation triggered by
// our own backtrace() / table insertion is caught by the tls_in_profiler
// guard inside record_allocation and skipped.
// =====================================================================

namespace {

std::atomic<bool> g_swizzle_enabled{false};
Method g_target_method = nullptr;
IMP g_original_imp = nullptr;

std::atomic<uint64_t> g_total_invocations{0};
std::atomic<uint64_t> g_observed_allocations{0};
std::atomic<uint64_t> g_skipped_disabled{0};

/// Trampoline that replaces +[NSObject allocWithZone:].
///
/// Signature must match the original class method exactly: (Class self,
/// SEL _cmd, struct _NSZone* zone). The Obj-C runtime invokes IMPs via
/// objc_msgSend, which arranges these arguments in registers — same ABI
/// as a C function pointer call.
id swizzled_alloc_with_zone(Class cls, SEL cmd, struct _NSZone* zone) {
    g_total_invocations.fetch_add(1, std::memory_order_relaxed);

    // Forward to the original implementation first. The instance comes
    // out fully constructed (or nil under allocation failure).
    using AllocFn = id(*)(Class, SEL, struct _NSZone*);
    id obj = reinterpret_cast<AllocFn>(g_original_imp)(cls, cmd, zone);

    if (!g_swizzle_enabled.load(std::memory_order_relaxed)) {
        g_skipped_disabled.fetch_add(1, std::memory_order_relaxed);
        return obj;
    }
    if (obj == nullptr) {
        return obj;
    }

    // class_getInstanceSize returns the ivar storage footprint — a
    // close enough proxy for the allocator's request size for the
    // spike. class_getName returns a stable C string tied to the class
    // metadata, safe to store as a borrowed pointer.
    const size_t size = class_getInstanceSize(cls);
    const char* name = class_getName(cls);
    dd_memory_observe_allocation(reinterpret_cast<const void*>(obj),
                                  static_cast<uint64_t>(size),
                                  name);
    g_observed_allocations.fetch_add(1, std::memory_order_relaxed);
    return obj;
}

void reset_swizzle_diagnostics() {
    g_total_invocations.store(0, std::memory_order_relaxed);
    g_observed_allocations.store(0, std::memory_order_relaxed);
    g_skipped_disabled.store(0, std::memory_order_relaxed);
}

} // namespace

extern "C" dd_memory_swizzle_status_t dd_memory_swizzle_start(uint64_t poisson_rate_bytes) {
    if (g_swizzle_enabled.load(std::memory_order_acquire)) {
        return DD_MEMORY_SWIZZLE_STATUS_ALREADY_INSTALLED;
    }

    if (!dd_memory_profiler_start_passive(poisson_rate_bytes)) {
        return DD_MEMORY_SWIZZLE_STATUS_FAILED_SAMPLER;
    }

    // Resolve +[NSObject allocWithZone:] via the runtime. allocWithZone:
    // is a class method, so we look up the method on NSObject's metaclass.
    Class nsobject_class = objc_getClass("NSObject");
    if (nsobject_class == nullptr) {
        return DD_MEMORY_SWIZZLE_STATUS_FAILED_NO_METHOD;
    }
    SEL alloc_sel = sel_registerName("allocWithZone:");
    Method method = class_getClassMethod(nsobject_class, alloc_sel);
    if (method == nullptr) {
        return DD_MEMORY_SWIZZLE_STATUS_FAILED_NO_METHOD;
    }

    reset_swizzle_diagnostics();
    g_target_method = method;
    g_original_imp = method_setImplementation(method,
                                               reinterpret_cast<IMP>(swizzled_alloc_with_zone));
    g_swizzle_enabled.store(true, std::memory_order_release);
    return DD_MEMORY_SWIZZLE_STATUS_OK;
}

extern "C" void dd_memory_swizzle_stop(void) {
    if (!g_swizzle_enabled.load(std::memory_order_acquire)) {
        return;
    }
    if (g_target_method != nullptr && g_original_imp != nullptr) {
        method_setImplementation(g_target_method, g_original_imp);
    }
    g_target_method = nullptr;
    g_original_imp = nullptr;
    g_swizzle_enabled.store(false, std::memory_order_release);
    dd_memory_profiler_stop();
}

extern "C" bool dd_memory_swizzle_is_running(void) {
    return g_swizzle_enabled.load(std::memory_order_acquire);
}

extern "C" dd_memory_swizzle_diagnostics_t dd_memory_swizzle_diagnostics(void) {
    dd_memory_swizzle_diagnostics_t d = {};
    d.total_invocations = g_total_invocations.load(std::memory_order_relaxed);
    d.observed_allocations = g_observed_allocations.load(std::memory_order_relaxed);
    d.skipped_disabled = g_skipped_disabled.load(std::memory_order_relaxed);
    return d;
}

#endif // defined(__APPLE__) && !TARGET_OS_WATCH
