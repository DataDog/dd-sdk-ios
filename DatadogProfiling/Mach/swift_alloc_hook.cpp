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

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <condition_variable>
#include <dlfcn.h>
#include <mutex>

namespace {

struct HeapObject;
struct HeapMetadata;

using AllocFn = HeapObject *(*)(HeapMetadata *, size_t, size_t);
using DeallocFn = void (*)(HeapObject *, size_t, size_t);
struct SwiftTypeName {
  const char *data;
  uintptr_t length;
};
using GetTypeNameFn = SwiftTypeName (*)(const HeapMetadata *, bool);

std::mutex g_install_mutex;
std::mutex g_drain_mutex;
std::condition_variable g_drain_condition;
enum class InstallState : std::uint8_t { neverAttempted, installed, failed };
InstallState g_install_state = InstallState::neverAttempted;
dd_swift_alloc_hook_status_t g_failure_status =
    DD_SWIFT_ALLOC_HOOK_FAILED_REBIND;

constexpr uint64_t kObservationEnabled = 0x8000000000000000ULL;
constexpr uint64_t kInFlightMask = ~kObservationEnabled;
// The enabled bit and callback count share one atomic so stop cannot miss a
// callback admitted just before it disables observation.
std::atomic<uint64_t> g_observation_state{0};
// A trampoline can pause in the Swift runtime across stop and restart. Such a
// call must not enter the replacement observer session when it resumes.
std::atomic<uint64_t> g_observation_generation{0};
std::atomic<dd_swift_allocation_observer_t> g_allocation_observer{nullptr};
std::atomic<dd_swift_deallocation_observer_t> g_deallocation_observer{nullptr};
std::atomic<AllocFn> g_runtime_alloc{nullptr};
std::atomic<DeallocFn> g_runtime_class_dealloc{nullptr};
std::atomic<DeallocFn> g_runtime_object_dealloc{nullptr};
std::atomic<GetTypeNameFn> g_get_type_name{nullptr};

// fishhook keeps these pointers for rebinding future images. Atomic builtins
// are also used by fishhook.c, so callback and hook threads can read safely.
void *g_first_alloc = nullptr;
void *g_first_class_dealloc = nullptr;
void *g_first_object_dealloc = nullptr;
uint64_t g_alloc_patches = 0;
uint64_t g_class_dealloc_patches = 0;
uint64_t g_object_dealloc_patches = 0;
uint64_t g_alloc_conflicts = 0;
uint64_t g_class_dealloc_conflicts = 0;
uint64_t g_object_dealloc_conflicts = 0;
uint64_t g_alloc_failures = 0;
uint64_t g_class_dealloc_failures = 0;
uint64_t g_object_dealloc_failures = 0;

std::atomic<uint64_t> g_allocations{0};
std::atomic<uint64_t> g_class_deallocations{0};
std::atomic<uint64_t> g_object_deallocations{0};
std::atomic<uint64_t> g_reentrant_skips{0};
thread_local bool t_observing = false;

uint64_t load_count(const uint64_t *count) {
  return __atomic_load_n(count, __ATOMIC_ACQUIRE);
}

uint64_t conflict_count() {
  return load_count(&g_alloc_conflicts) +
         load_count(&g_class_dealloc_conflicts) +
         load_count(&g_object_dealloc_conflicts);
}

uint64_t failure_count() {
  return load_count(&g_alloc_failures) +
         load_count(&g_class_dealloc_failures) +
         load_count(&g_object_dealloc_failures);
}

bool observing() {
  return (g_observation_state.load(std::memory_order_acquire) &
          kObservationEnabled) != 0 &&
         conflict_count() == 0 && failure_count() == 0;
}

void release_observation() {
  const uint64_t prior =
      g_observation_state.fetch_sub(1, std::memory_order_acq_rel);
  if ((prior & kInFlightMask) == 1 &&
      (prior & kObservationEnabled) == 0) {
    std::lock_guard<std::mutex> lock(g_drain_mutex);
    g_drain_condition.notify_all();
  }
}

bool begin_observation(uint64_t generation) {
  if ((g_observation_state.load(std::memory_order_acquire) &
       kObservationEnabled) == 0) {
    return false;
  }
  const uint64_t prior =
      g_observation_state.fetch_add(1, std::memory_order_acq_rel);
  if ((prior & kObservationEnabled) != 0 &&
      g_observation_generation.load(std::memory_order_acquire) == generation) {
    return true;
  }
  // Stop or restart changed the observer session before admission.
  release_observation();
  return false;
}

// Call only while holding g_install_mutex. Start uses the same drain before
// replacing observers, so an admitted callback cannot switch to a new one.
void disable_and_drain_observation() {
  g_observation_state.fetch_and(kInFlightMask, std::memory_order_acq_rel);
  std::unique_lock<std::mutex> lock(g_drain_mutex);
  g_drain_condition.wait(lock, [] {
    return (g_observation_state.load(std::memory_order_acquire) &
            kInFlightMask) == 0;
  });
}

template <typename Function>
Function previous(void *const *slot, const std::atomic<Function> &runtime) {
  void *prior = __atomic_load_n(slot, __ATOMIC_ACQUIRE);
  return prior != nullptr ? reinterpret_cast<Function>(prior)
                          : runtime.load(std::memory_order_acquire);
}

// Swift's heap-local-variable and error-object metadata have no nominal type.
// The first metadata word is a small kind value; class metadata starts with an
// isa pointer. This mirrors the guard exercised in the memory-profiling PoC.
bool has_nominal_type(const HeapMetadata *metadata) {
  if (metadata == nullptr) {
    return false;
  }
  uintptr_t kind = *reinterpret_cast<const uintptr_t *>(metadata);
  return kind < 0x400 || kind >= 0x800;
}

dd_swift_class_name_t resolve_class_name(const void *metadata) {
  auto get_name = g_get_type_name.load(std::memory_order_acquire);
  if (get_name == nullptr ||
      !has_nominal_type(static_cast<const HeapMetadata *>(metadata))) {
    return {nullptr, 0};
  }
  SwiftTypeName name =
      get_name(static_cast<const HeapMetadata *>(metadata), false);
  return name.data != nullptr ? dd_swift_class_name_t{name.data, name.length}
                              : dd_swift_class_name_t{nullptr, 0};
}

HeapObject *intercept_alloc(HeapMetadata *metadata, size_t size,
                            size_t alignment_mask) {
  const uint64_t generation =
      g_observation_generation.load(std::memory_order_acquire);
  AllocFn original = previous(&g_first_alloc, g_runtime_alloc);
  HeapObject *object = original(metadata, size, alignment_mask);
  if (!observing() || object == nullptr || !has_nominal_type(metadata)) {
    return object;
  }
  if (t_observing) {
    g_reentrant_skips.fetch_add(1, std::memory_order_relaxed);
    return object;
  }
  if (!begin_observation(generation)) {
    return object;
  }

  t_observing = true;
  g_allocations.fetch_add(1, std::memory_order_relaxed);
  auto observer = g_allocation_observer.load(std::memory_order_acquire);
  if (observer != nullptr) {
    observer(object, static_cast<uint64_t>(size), metadata, resolve_class_name);
  }
  t_observing = false;
  release_observation();
  return object;
}

void observe_deallocation(const HeapObject *object,
                          std::atomic<uint64_t> &counter) {
  const uint64_t generation =
      g_observation_generation.load(std::memory_order_acquire);
  if (!observing() || object == nullptr) {
    return;
  }
  if (t_observing) {
    g_reentrant_skips.fetch_add(1, std::memory_order_relaxed);
    return;
  }
  if (!begin_observation(generation)) {
    return;
  }

  t_observing = true;
  counter.fetch_add(1, std::memory_order_relaxed);
  auto observer = g_deallocation_observer.load(std::memory_order_acquire);
  if (observer != nullptr) {
    // These entry points may run before storage is freed if unowned references
    // remain. Both can report an address, so observers must deduplicate it.
    observer(object);
  }
  t_observing = false;
  release_observation();
}

void intercept_class_dealloc(HeapObject *object, size_t size,
                             size_t alignment_mask) {
  observe_deallocation(object, g_class_deallocations);
  DeallocFn original =
      previous(&g_first_class_dealloc, g_runtime_class_dealloc);
  original(object, size, alignment_mask);
}

void intercept_object_dealloc(HeapObject *object, size_t size,
                              size_t alignment_mask) {
  observe_deallocation(object, g_object_deallocations);
  DeallocFn original =
      previous(&g_first_object_dealloc, g_runtime_object_dealloc);
  original(object, size, alignment_mask);
}

} // namespace

extern "C" dd_swift_alloc_hook_status_t dd_swift_alloc_hook_start(
    dd_swift_allocation_observer_t allocation_observer,
    dd_swift_deallocation_observer_t deallocation_observer) {
  if (allocation_observer == nullptr || deallocation_observer == nullptr) {
    return DD_SWIFT_ALLOC_HOOK_FAILED_INVALID_OBSERVER;
  }

  std::lock_guard<std::mutex> lock(g_install_mutex);
  if (g_install_state == InstallState::installed) {
    disable_and_drain_observation();
    if (failure_count() != 0) {
      g_install_state = InstallState::failed;
      g_failure_status = DD_SWIFT_ALLOC_HOOK_FAILED_REBIND;
      return g_failure_status;
    }
    if (conflict_count() != 0) {
      g_install_state = InstallState::failed;
      g_failure_status = DD_SWIFT_ALLOC_HOOK_FAILED_CONFLICT;
      return g_failure_status;
    }
    g_allocation_observer.store(allocation_observer, std::memory_order_release);
    g_deallocation_observer.store(deallocation_observer,
                                  std::memory_order_release);
    g_observation_generation.fetch_add(1, std::memory_order_acq_rel);
    g_observation_state.fetch_or(kObservationEnabled,
                                 std::memory_order_release);
    return DD_SWIFT_ALLOC_HOOK_ALREADY_INSTALLED;
  }
  if (g_install_state == InstallState::failed) {
    return g_failure_status;
  }

  // Resolve every forward target before any import slot can point at a
  // trampoline. A partial rebind must never make an app call a null pointer.
  void *alloc_symbol = dlsym(RTLD_DEFAULT, "swift_allocObject");
  void *class_dealloc_symbol =
      dlsym(RTLD_DEFAULT, "swift_deallocClassInstance");
  void *object_dealloc_symbol = dlsym(RTLD_DEFAULT, "swift_deallocObject");
  auto alloc = reinterpret_cast<AllocFn>(alloc_symbol);
  auto class_dealloc = reinterpret_cast<DeallocFn>(class_dealloc_symbol);
  auto object_dealloc = reinterpret_cast<DeallocFn>(object_dealloc_symbol);
  auto get_name =
      reinterpret_cast<GetTypeNameFn>(dlsym(RTLD_DEFAULT, "swift_getTypeName"));
  if (alloc == nullptr || class_dealloc == nullptr ||
      object_dealloc == nullptr || get_name == nullptr) {
    return DD_SWIFT_ALLOC_HOOK_FAILED_NO_SYMBOL;
  }
  g_runtime_alloc.store(alloc, std::memory_order_release);
  g_runtime_class_dealloc.store(class_dealloc, std::memory_order_release);
  g_runtime_object_dealloc.store(object_dealloc, std::memory_order_release);
  g_get_type_name.store(get_name, std::memory_order_release);

  // first_replaced is published before a slot is patched. fishhook leaves
  // slots with a different previous implementation untouched, because a
  // single trampoline cannot safely forward through two different chains.
  struct rebinding bindings[] = {
      {"swift_allocObject", reinterpret_cast<void *>(intercept_alloc), nullptr,
       &g_first_alloc, &g_alloc_patches, &g_alloc_conflicts,
       &g_alloc_failures, alloc_symbol,
      },
      {"swift_deallocClassInstance",
       reinterpret_cast<void *>(intercept_class_dealloc), nullptr,
       &g_first_class_dealloc, &g_class_dealloc_patches,
       &g_class_dealloc_conflicts, &g_class_dealloc_failures,
       class_dealloc_symbol,
      },
      {"swift_deallocObject",
       reinterpret_cast<void *>(intercept_object_dealloc), nullptr,
       &g_first_object_dealloc, &g_object_dealloc_patches,
       &g_object_dealloc_conflicts, &g_object_dealloc_failures,
       object_dealloc_symbol,
      },
  };
  int result = rebind_symbols(bindings, sizeof(bindings) / sizeof(bindings[0]));
  g_install_state =
      InstallState::failed; // fishhook cannot unregister a partial install
  if (result != 0 || failure_count() != 0 ||
      load_count(&g_alloc_patches) == 0 ||
      load_count(&g_class_dealloc_patches) == 0) {
    g_failure_status = DD_SWIFT_ALLOC_HOOK_FAILED_REBIND;
    return DD_SWIFT_ALLOC_HOOK_FAILED_REBIND;
  }
  if (conflict_count() != 0) {
    g_failure_status = DD_SWIFT_ALLOC_HOOK_FAILED_CONFLICT;
    return DD_SWIFT_ALLOC_HOOK_FAILED_CONFLICT;
  }

  g_allocation_observer.store(allocation_observer, std::memory_order_release);
  g_deallocation_observer.store(deallocation_observer,
                                std::memory_order_release);
  g_install_state = InstallState::installed;
  g_observation_generation.fetch_add(1, std::memory_order_acq_rel);
  g_observation_state.fetch_or(kObservationEnabled,
                               std::memory_order_release);
  return DD_SWIFT_ALLOC_HOOK_OK;
}

extern "C" void dd_swift_alloc_hook_stop(void) {
  // Never restore patched import slots: another rebinder may now own them.
  std::lock_guard<std::mutex> lock(g_install_mutex);
  disable_and_drain_observation();
}

extern "C" dd_swift_alloc_hook_diagnostics_t
dd_swift_alloc_hook_diagnostics(void) {
  dd_swift_alloc_hook_diagnostics_t result{};
  result.allocations = g_allocations.load(std::memory_order_relaxed);
  result.class_deallocations =
      g_class_deallocations.load(std::memory_order_relaxed);
  result.object_deallocations =
      g_object_deallocations.load(std::memory_order_relaxed);
  result.reentrant_skips = g_reentrant_skips.load(std::memory_order_relaxed);
  result.alloc_slots_patched = load_count(&g_alloc_patches);
  result.class_dealloc_slots_patched = load_count(&g_class_dealloc_patches);
  result.object_dealloc_slots_patched = load_count(&g_object_dealloc_patches);
  result.conflicting_slots = conflict_count();
  result.failed_slot_writes = failure_count();
  result.is_enabled = observing();
  return result;
}

#endif // !TARGET_OS_WATCH
#endif // __APPLE__
