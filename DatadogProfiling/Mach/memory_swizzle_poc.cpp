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
// +allocWithZone: / -dealloc Swizzling Spike (follow-up to RUM-16460)
//
// Strategy:
//   1. Resolve +[NSObject allocWithZone:] and -[NSObject dealloc] via
//      the Obj-C runtime (no @selector / no Obj-C source — runtime API
//      is plain C).
//   2. Replace their IMPs with trampolines using method_setImplementation.
//      Previous IMPs are stored so calls can be forwarded and restored.
//   3. Allocation invocations forward first, then report the new instance
//      and class to the passive sampler. Deallocation invocations remove
//      the instance from the live table before forwarding.
//
// The trampoline writes through the same Poisson sampler / reentrancy
// guard / side-table as the zone-hook path: any allocation triggered by
// our own backtrace() / table insertion is caught by the tls_in_profiler
// guard inside record_allocation and skipped.
// =====================================================================

namespace {

std::atomic<bool> g_swizzle_enabled{false};
Method g_alloc_method = nullptr;
Method g_dealloc_method = nullptr;
std::atomic<IMP> g_original_alloc_imp{nullptr};
std::atomic<IMP> g_original_dealloc_imp{nullptr};
bool g_alloc_layer_installed = false;
bool g_dealloc_layer_installed = false;

std::atomic<uint64_t> g_total_invocations{0};
std::atomic<uint64_t> g_observed_allocations{0};
std::atomic<uint64_t> g_skipped_disabled{0};
std::atomic<uint64_t> g_total_dealloc_invocations{0};
std::atomic<uint64_t> g_observed_deallocations{0};
std::atomic<uint64_t> g_skipped_dealloc_disabled{0};

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
    const IMP original = g_original_alloc_imp.load(std::memory_order_acquire);
    id obj = reinterpret_cast<AllocFn>(original)(cls, cmd, zone);

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

/// Trampoline that replaces -[NSObject dealloc].
///
/// Recording must happen before forwarding because the original implementation
/// releases the object's storage. This function must never message or retain
/// `obj`; the observer treats it only as an address.
void swizzled_dealloc(id obj, SEL cmd) {
    g_total_dealloc_invocations.fetch_add(1, std::memory_order_relaxed);

    if (g_swizzle_enabled.load(std::memory_order_relaxed)) {
        dd_memory_observe_deallocation(reinterpret_cast<const void*>(obj));
        g_observed_deallocations.fetch_add(1, std::memory_order_relaxed);
    } else {
        g_skipped_dealloc_disabled.fetch_add(1, std::memory_order_relaxed);
    }

    using DeallocFn = void(*)(id, SEL);
    const IMP original = g_original_dealloc_imp.load(std::memory_order_acquire);
    reinterpret_cast<DeallocFn>(original)(obj, cmd);
}

void reset_swizzle_diagnostics() {
    g_total_invocations.store(0, std::memory_order_relaxed);
    g_observed_allocations.store(0, std::memory_order_relaxed);
    g_skipped_disabled.store(0, std::memory_order_relaxed);
    g_total_dealloc_invocations.store(0, std::memory_order_relaxed);
    g_observed_deallocations.store(0, std::memory_order_relaxed);
    g_skipped_dealloc_disabled.store(0, std::memory_order_relaxed);
}

} // namespace

extern "C" dd_memory_swizzle_status_t dd_memory_swizzle_start(uint64_t poisson_rate_bytes) {
    if (g_swizzle_enabled.load(std::memory_order_acquire)) {
        return DD_MEMORY_SWIZZLE_STATUS_ALREADY_INSTALLED;
    }

    // Resolve both methods before starting the sampler so a missing runtime
    // method cannot leave passive profiling enabled without interception.
    Class nsobject_class = objc_getClass("NSObject");
    if (nsobject_class == nullptr) {
        return DD_MEMORY_SWIZZLE_STATUS_FAILED_NO_METHOD;
    }
    SEL alloc_sel = sel_registerName("allocWithZone:");
    SEL dealloc_sel = sel_registerName("dealloc");
    Method alloc_method = class_getClassMethod(nsobject_class, alloc_sel);
    Method dealloc_method = class_getInstanceMethod(nsobject_class, dealloc_sel);
    if (alloc_method == nullptr || dealloc_method == nullptr) {
        return DD_MEMORY_SWIZZLE_STATUS_FAILED_NO_METHOD;
    }

    if (!dd_memory_profiler_start_passive(poisson_rate_bytes)) {
        return DD_MEMORY_SWIZZLE_STATUS_FAILED_SAMPLER;
    }

    reset_swizzle_diagnostics();
    g_alloc_method = alloc_method;
    g_dealloc_method = dealloc_method;

    if (!g_alloc_layer_installed) {
        // Prime the forwarding pointer before publishing the trampoline. The
        // value returned by method_setImplementation is stored again to retain
        // the exact outermost implementation present at installation time.
        g_original_alloc_imp.store(method_getImplementation(alloc_method),
                                   std::memory_order_release);
        const IMP previous = method_setImplementation(
            alloc_method,
            reinterpret_cast<IMP>(swizzled_alloc_with_zone)
        );
        g_original_alloc_imp.store(previous, std::memory_order_release);
        g_alloc_layer_installed = true;
    }

    if (!g_dealloc_layer_installed) {
        g_original_dealloc_imp.store(method_getImplementation(dealloc_method),
                                     std::memory_order_release);
        const IMP previous = method_setImplementation(
            dealloc_method,
            reinterpret_cast<IMP>(swizzled_dealloc)
        );
        g_original_dealloc_imp.store(previous, std::memory_order_release);
        g_dealloc_layer_installed = true;
    }

    g_swizzle_enabled.store(true, std::memory_order_release);
    return DD_MEMORY_SWIZZLE_STATUS_OK;
}

extern "C" void dd_memory_swizzle_stop(void) {
    if (!g_swizzle_enabled.exchange(false, std::memory_order_acq_rel)) {
        return;
    }

    // Disable observation before touching either IMP. In-flight trampolines
    // retain stable forwarding pointers and will still reach the next layer.
    dd_memory_profiler_stop();

    if (g_dealloc_layer_installed
        && g_dealloc_method != nullptr
        && method_getImplementation(g_dealloc_method) == reinterpret_cast<IMP>(swizzled_dealloc)) {
        method_setImplementation(
            g_dealloc_method,
            g_original_dealloc_imp.load(std::memory_order_acquire)
        );
        g_dealloc_layer_installed = false;
    }

    if (g_alloc_layer_installed
        && g_alloc_method != nullptr
        && method_getImplementation(g_alloc_method) == reinterpret_cast<IMP>(swizzled_alloc_with_zone)) {
        method_setImplementation(
            g_alloc_method,
            g_original_alloc_imp.load(std::memory_order_acquire)
        );
        g_alloc_layer_installed = false;
    }
}

extern "C" bool dd_memory_swizzle_is_running(void) {
    return g_swizzle_enabled.load(std::memory_order_acquire);
}

extern "C" dd_memory_swizzle_diagnostics_t dd_memory_swizzle_diagnostics(void) {
    dd_memory_swizzle_diagnostics_t d = {};
    d.total_invocations = g_total_invocations.load(std::memory_order_relaxed);
    d.observed_allocations = g_observed_allocations.load(std::memory_order_relaxed);
    d.skipped_disabled = g_skipped_disabled.load(std::memory_order_relaxed);
    d.total_dealloc_invocations = g_total_dealloc_invocations.load(std::memory_order_relaxed);
    d.observed_deallocations = g_observed_deallocations.load(std::memory_order_relaxed);
    d.skipped_dealloc_disabled = g_skipped_dealloc_disabled.load(std::memory_order_relaxed);
    return d;
}

#endif // defined(__APPLE__) && !TARGET_OS_WATCH
