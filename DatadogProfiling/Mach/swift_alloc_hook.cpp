/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "swift_alloc_hook.h"

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#include "fishhook.h"
#include "memory_profiler.h"

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <dlfcn.h>
#include <mutex>
#include <unordered_set>

namespace {

// Opaque Swift runtime types. We only ever pass these pointers through.
struct HeapObject;
struct HeapMetadata;

// swift_allocObject(metadata, requiredSize, requiredAlignmentMask) -> object.
// swift_deallocClassInstance(object, allocatedSize, allocatedAlignMask).
// Both use the C calling convention (SWIFT_RUNTIME_EXPORT / __cdecl-compatible).
using AllocFn = HeapObject *(*)(HeapMetadata *, size_t, size_t);
using DeallocFn = void (*)(HeapObject *, size_t, size_t);

// swift_getTypeName(metadata, qualified) -> { malloc'd C string, length }.
struct SwiftTypeNamePair { const char *data; uintptr_t length; };
using GetTypeNameFn = SwiftTypeNamePair (*)(const HeapMetadata *, bool);

std::atomic<AllocFn> g_orig_alloc{nullptr};
std::atomic<DeallocFn> g_orig_dealloc{nullptr};
std::atomic<DeallocFn> g_orig_dealloc_object{nullptr};

std::atomic<bool> g_installed{false};
std::atomic<bool> g_enabled{false};

std::atomic<uint64_t> g_alloc_invocations{0};
std::atomic<uint64_t> g_dealloc_invocations{0};
std::atomic<uint64_t> g_dealloc_object_invocations{0};
std::atomic<uint64_t> g_reentrant_skips{0};
std::atomic<bool> g_alloc_bound{false};
std::atomic<bool> g_dealloc_bound{false};

// swift_getTypeName resolver, resolved once and cached.
std::atomic<GetTypeNameFn> g_get_type_name{nullptr};

// Fixed-size, allocation-free metadata -> demangled name cache. Open-addressed;
// never rehashes or grows, so it is safe to touch from the allocation hot path
// (unlike a std::unordered_map, whose rehash mallocs on every growth). Writes
// are serialized by g_name_mutex; reads are lock-free via the atomic metadata
// key, which is published only after the name pointer is written. strdup runs
// at most once per unique type (bounded by the capacity), never per allocation.
constexpr size_t NAME_CACHE_CAPACITY = 1024;  // power of two
static_assert((NAME_CACHE_CAPACITY & (NAME_CACHE_CAPACITY - 1)) == 0,
              "NAME_CACHE_CAPACITY must be a power of two");

struct NameCacheEntry {
    std::atomic<const void *> metadata{nullptr};
    const char *name{nullptr};
};
NameCacheEntry g_name_cache[NAME_CACHE_CAPACITY];
std::mutex g_name_mutex;

size_t name_bucket(const void *metadata) {
    uintptr_t v = reinterpret_cast<uintptr_t>(metadata) >> 4;
    v ^= v >> 30;
    v *= 0xbf58476d1ce4e5b9ULL;
    v ^= v >> 27;
    return static_cast<size_t>(v) & (NAME_CACHE_CAPACITY - 1);
}

// One-shot capture for the spike tests. thread_local arm flag keeps it
// deterministic per test; the captured slot is global.
thread_local bool t_in_hook = false;
thread_local bool t_arm_capture = false;
std::atomic<HeapMetadata *> g_captured_metadata{nullptr};
std::atomic<uint64_t> g_captured_size{0};

// SQ4 free-side / live-set validation. Only allocations whose type metadata
// has been registered by the test are tracked, so the process-wide hook does
// not fill the set with unrelated Swift allocations. `g_track_enabled` gates
// the locked section so there is zero cost in production (nothing registers).
std::atomic<bool> g_track_enabled{false};
std::mutex g_track_mutex;
std::unordered_set<const void *> g_registered_metadata;
std::unordered_set<const void *> g_live_addresses;

// Resolve the demangled type name for a metadata pointer, caching a leak-once
// stable copy. Runs only from inside the reentrancy guard. Returns nullptr if
// the runtime symbol is unavailable or resolution fails.
const char *resolve_type_name(HeapMetadata *metadata) {
    if (metadata == nullptr) {
        return nullptr;
    }
    const void *key = static_cast<const void *>(metadata);
    const size_t start = name_bucket(key);

    // Lock-free read probe. An empty slot terminates the chain (nothing was
    // ever inserted past it for this bucket).
    for (size_t i = 0; i < NAME_CACHE_CAPACITY; ++i) {
        NameCacheEntry &e = g_name_cache[(start + i) & (NAME_CACHE_CAPACITY - 1)];
        const void *m = e.metadata.load(std::memory_order_acquire);
        if (m == key) {
            return e.name;
        }
        if (m == nullptr) {
            break;
        }
    }

    // Resolve the runtime symbol once.
    GetTypeNameFn getName = g_get_type_name.load(std::memory_order_acquire);
    if (getName == nullptr) {
        getName = reinterpret_cast<GetTypeNameFn>(dlsym(RTLD_DEFAULT, "swift_getTypeName"));
        if (getName == nullptr) {
            return nullptr;
        }
        g_get_type_name.store(getName, std::memory_order_release);
    }

    std::lock_guard<std::mutex> lock(g_name_mutex);
    // Re-probe under the lock: another thread may have inserted meanwhile, or we
    // claim the first empty slot for this key.
    for (size_t i = 0; i < NAME_CACHE_CAPACITY; ++i) {
        NameCacheEntry &e = g_name_cache[(start + i) & (NAME_CACHE_CAPACITY - 1)];
        const void *m = e.metadata.load(std::memory_order_relaxed);
        if (m == key) {
            return e.name;
        }
        if (m == nullptr) {
            // swift_getTypeName returns a runtime-cached, process-stable pointer
            // for a given metadata (repeated calls return the same buffer). Do
            // NOT free it — the runtime owns it — and do NOT copy it; caching the
            // pointer directly is both correct and allocation-free.
            SwiftTypeNamePair pair = getName(metadata, /*qualified=*/false);
            const char *stable = pair.data;
            e.name = stable;                                   // publish name first
            e.metadata.store(key, std::memory_order_release);  // then the key
            return stable;
        }
    }
    // Cache full: degrade to no class name (bounded, no per-alloc leak).
    return nullptr;
}

HeapObject *trampoline_alloc(HeapMetadata *metadata, size_t size, size_t alignMask) {
    // Forward first so the object exists regardless of our bookkeeping.
    AllocFn orig = g_orig_alloc.load(std::memory_order_acquire);
    HeapObject *obj = orig(metadata, size, alignMask);

    if (!g_enabled.load(std::memory_order_relaxed)) {
        return obj;
    }
    if (t_in_hook) {
        g_reentrant_skips.fetch_add(1, std::memory_order_relaxed);
        return obj;
    }
    t_in_hook = true;

    g_alloc_invocations.fetch_add(1, std::memory_order_relaxed);
    if (t_arm_capture) {
        g_captured_metadata.store(metadata, std::memory_order_relaxed);
        g_captured_size.store(size, std::memory_order_relaxed);
        t_arm_capture = false;
    }
    if (g_track_enabled.load(std::memory_order_relaxed)) {
        std::lock_guard<std::mutex> lock(g_track_mutex);
        if (g_registered_metadata.count(static_cast<const void *>(metadata)) != 0) {
            g_live_addresses.insert(static_cast<const void *>(obj));
        }
    }

    // Production path: record into the shared sampler/live-set/encoder pipeline.
    // Name resolution and observe run inside the reentrancy guard, so any
    // allocation they trigger short-circuits (t_in_hook) instead of recursing.
    const char *name = resolve_type_name(metadata);
    dd_memory_observe_allocation_with_source(
        static_cast<const void *>(obj),
        static_cast<uint64_t>(size),
        name,
        DD_MEMORY_SOURCE_SWIFT);

    t_in_hook = false;
    return obj;
}

void trampoline_dealloc(HeapObject *object, size_t size, size_t alignMask) {
    if (g_enabled.load(std::memory_order_relaxed) && !t_in_hook) {
        g_dealloc_invocations.fetch_add(1, std::memory_order_relaxed);
        dd_memory_observe_deallocation(static_cast<const void *>(object));
        if (g_track_enabled.load(std::memory_order_relaxed)) {
            std::lock_guard<std::mutex> lock(g_track_mutex);
            g_live_addresses.erase(static_cast<const void *>(object));
        }
    }
    DeallocFn orig = g_orig_dealloc.load(std::memory_order_acquire);
    orig(object, size, alignMask);
}

// Defensive second free path. swift_deallocObject shares the (object, size,
// alignMask) ABI and may run instead of / in addition to
// swift_deallocClassInstance. dd_memory_observe_deallocation is idempotent by
// address, so a double-fire is harmless; the separate counter lets us see in
// practice whether this path ever runs (RUM-16460 open question).
void trampoline_dealloc_object(HeapObject *object, size_t size, size_t alignMask) {
    if (g_enabled.load(std::memory_order_relaxed) && !t_in_hook) {
        g_dealloc_object_invocations.fetch_add(1, std::memory_order_relaxed);
        dd_memory_observe_deallocation(static_cast<const void *>(object));
        if (g_track_enabled.load(std::memory_order_relaxed)) {
            std::lock_guard<std::mutex> lock(g_track_mutex);
            g_live_addresses.erase(static_cast<const void *>(object));
        }
    }
    DeallocFn orig = g_orig_dealloc_object.load(std::memory_order_acquire);
    if (orig != nullptr) {
        orig(object, size, alignMask);
    }
}

} // namespace

extern "C" dd_swift_alloc_hook_status_t dd_swift_alloc_hook_start(uint64_t poisson_rate_bytes) {
    // Bring up (or join) the shared passive sampler. Idempotent: if the Obj-C
    // swizzle already started it, this leaves the active session untouched.
    if (!dd_memory_profiler_start_passive(poisson_rate_bytes)) {
        return DD_SWIFT_ALLOC_HOOK_FAILED_NO_SYMBOL;
    }

    if (g_installed.exchange(true)) {
        g_enabled.store(true, std::memory_order_release);
        return DD_SWIFT_ALLOC_HOOK_ALREADY_INSTALLED;
    }

    // Pre-resolve the originals so the trampolines always have a valid forward
    // target, even if another thread calls through a rebound slot mid-install.
    auto alloc = reinterpret_cast<AllocFn>(dlsym(RTLD_DEFAULT, "swift_allocObject"));
    auto dealloc = reinterpret_cast<DeallocFn>(dlsym(RTLD_DEFAULT, "swift_deallocClassInstance"));
    auto deallocObj = reinterpret_cast<DeallocFn>(dlsym(RTLD_DEFAULT, "swift_deallocObject"));
    if (alloc == nullptr) {
        g_installed.store(false, std::memory_order_release);
        return DD_SWIFT_ALLOC_HOOK_FAILED_NO_SYMBOL;
    }
    g_orig_alloc.store(alloc, std::memory_order_release);
    if (dealloc != nullptr) {
        g_orig_dealloc.store(dealloc, std::memory_order_release);
    }
    if (deallocObj != nullptr) {
        g_orig_dealloc_object.store(deallocObj, std::memory_order_release);
    }

    g_enabled.store(true, std::memory_order_release);

    // fishhook writes the previous slot value (== the real runtime function)
    // back into these, and rebinds current + future images.
    static void *replaced_alloc = nullptr;
    static void *replaced_dealloc = nullptr;
    static void *replaced_dealloc_object = nullptr;
    struct rebinding rebindings[3] = {
        {"swift_allocObject", reinterpret_cast<void *>(trampoline_alloc), &replaced_alloc},
        {"swift_deallocClassInstance", reinterpret_cast<void *>(trampoline_dealloc), &replaced_dealloc},
        {"swift_deallocObject", reinterpret_cast<void *>(trampoline_dealloc_object), &replaced_dealloc_object},
    };
    // Multi-SDK compose stance: fishhook writes the previous slot value into
    // `replaced_*`, which becomes our forward target. If another library
    // rebinds these symbols BEFORE us, we chain on top of theirs (their
    // function is our `orig`, and it still runs). If another rebinds AFTER us,
    // our trampoline is bypassed for future images but our already-bound slots
    // keep working; g_installed makes re-entry idempotent. We never restore
    // (see dd_swift_alloc_hook_stop), mirroring the Obj-C zone-hook stance.
    rebind_symbols(rebindings, 3);

    if (replaced_alloc != nullptr) {
        g_orig_alloc.store(reinterpret_cast<AllocFn>(replaced_alloc), std::memory_order_release);
        g_alloc_bound.store(true, std::memory_order_relaxed);
    }
    if (replaced_dealloc != nullptr) {
        g_orig_dealloc.store(reinterpret_cast<DeallocFn>(replaced_dealloc), std::memory_order_release);
        g_dealloc_bound.store(true, std::memory_order_relaxed);
    }
    if (replaced_dealloc_object != nullptr) {
        g_orig_dealloc_object.store(reinterpret_cast<DeallocFn>(replaced_dealloc_object), std::memory_order_release);
    }

    return DD_SWIFT_ALLOC_HOOK_OK;
}

extern "C" void dd_swift_alloc_hook_stop(void) {
    // Never-restore: leave the trampolines installed, just stop recording.
    g_enabled.store(false, std::memory_order_release);
}

extern "C" dd_swift_alloc_hook_diagnostics_t dd_swift_alloc_hook_diagnostics(void) {
    dd_swift_alloc_hook_diagnostics_t diag;
    diag.alloc_invocations = g_alloc_invocations.load(std::memory_order_relaxed);
    diag.dealloc_invocations = g_dealloc_invocations.load(std::memory_order_relaxed);
    diag.dealloc_object_invocations = g_dealloc_object_invocations.load(std::memory_order_relaxed);
    diag.reentrant_skips = g_reentrant_skips.load(std::memory_order_relaxed);
    diag.alloc_bound = g_alloc_bound.load(std::memory_order_relaxed);
    diag.dealloc_bound = g_dealloc_bound.load(std::memory_order_relaxed);
    return diag;
}

extern "C" void dd_swift_alloc_test_reset(void) {
    g_alloc_invocations.store(0, std::memory_order_relaxed);
    g_dealloc_invocations.store(0, std::memory_order_relaxed);
    g_dealloc_object_invocations.store(0, std::memory_order_relaxed);
    g_reentrant_skips.store(0, std::memory_order_relaxed);
    g_captured_metadata.store(nullptr, std::memory_order_relaxed);
    g_captured_size.store(0, std::memory_order_relaxed);
    t_arm_capture = false;
    {
        std::lock_guard<std::mutex> lock(g_track_mutex);
        g_registered_metadata.clear();
        g_live_addresses.clear();
    }
    g_track_enabled.store(false, std::memory_order_release);
}

extern "C" void dd_swift_alloc_test_register_class(void *metadata) {
    std::lock_guard<std::mutex> lock(g_track_mutex);
    g_registered_metadata.insert(static_cast<const void *>(metadata));
    g_track_enabled.store(true, std::memory_order_release);
}

extern "C" uint64_t dd_swift_alloc_test_live_count(void) {
    std::lock_guard<std::mutex> lock(g_track_mutex);
    return static_cast<uint64_t>(g_live_addresses.size());
}

extern "C" bool dd_swift_alloc_test_is_live(void *address) {
    std::lock_guard<std::mutex> lock(g_track_mutex);
    return g_live_addresses.count(static_cast<const void *>(address)) != 0;
}

extern "C" void dd_swift_alloc_test_arm_capture(void) {
    t_arm_capture = true;
}

extern "C" uint64_t dd_swift_alloc_test_captured_size(void) {
    return g_captured_size.load(std::memory_order_relaxed);
}

extern "C" uint64_t dd_swift_alloc_test_captured_name(char *buf, uint64_t buf_len) {
    if (buf == nullptr || buf_len == 0) {
        return 0;
    }
    buf[0] = '\0';
    HeapMetadata *metadata = g_captured_metadata.load(std::memory_order_relaxed);
    if (metadata == nullptr) {
        return 0;
    }
    auto getTypeName = reinterpret_cast<GetTypeNameFn>(dlsym(RTLD_DEFAULT, "swift_getTypeName"));
    if (getTypeName == nullptr) {
        return 0;
    }
    // Resolve off the hot path. The result string is malloc'd; we own it.
    SwiftTypeNamePair pair = getTypeName(metadata, /*qualified=*/false);
    if (pair.data == nullptr) {
        return 0;
    }
    uint64_t n = pair.length;
    if (n > buf_len - 1) {
        n = buf_len - 1;
    }
    memcpy(buf, pair.data, n);
    buf[n] = '\0';
    // Do not free pair.data: swift_getTypeName returns a runtime-cached,
    // process-stable pointer (repeated calls return the same buffer), so
    // freeing it here would corrupt the heap for any later caller.
    return n;
}

#endif // !TARGET_OS_WATCH
#endif // __APPLE__
