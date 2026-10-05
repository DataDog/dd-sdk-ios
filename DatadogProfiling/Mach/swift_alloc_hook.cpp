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
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <dlfcn.h>
#include <mutex>
#include <new>

namespace {

struct HeapObject;

using AllocFn = HeapObject *(*)(HeapMetadata *, size_t, size_t);
using DeallocFn = void (*)(HeapObject *, size_t, size_t);
using PartialClassDeallocFn = void (*)(HeapObject *, const HeapMetadata *,
                                      size_t, size_t);
struct SwiftTypeName {
  const char *data;
  uintptr_t length;
};
using GetTypeNameFn = SwiftTypeName (*)(const HeapMetadata *, bool);

class SwiftAllocHook {
public:
  SwiftAllocHook() = default;
  ~SwiftAllocHook() = default;
  SwiftAllocHook(const SwiftAllocHook &) = delete;
  SwiftAllocHook &operator=(const SwiftAllocHook &) = delete;
  SwiftAllocHook(SwiftAllocHook &&) = delete;
  SwiftAllocHook &operator=(SwiftAllocHook &&) = delete;

  dd_swift_alloc_hook_status_t
  start(dd_swift_allocation_observer_t allocation_observer,
        dd_swift_deallocation_observer_t deallocation_observer);
  void stop();
  dd_swift_alloc_hook_diagnostics_t diagnostics() const;

  HeapObject *interceptAlloc(HeapMetadata *metadata, size_t size,
                             size_t alignment_mask);
  void interceptClassDealloc(HeapObject *object, size_t size,
                             size_t alignment_mask);
  void interceptPartialClassDealloc(HeapObject *object,
                                    const HeapMetadata *metadata, size_t size,
                                    size_t alignment_mask);
  void interceptObjectDealloc(HeapObject *object, size_t size,
                              size_t alignment_mask);
  dd_swift_class_name_t resolveClassName(const HeapMetadata *metadata) const;

private:
  enum class InstallState : std::uint8_t { neverAttempted, installed, failed };
  static constexpr uint64_t kObservationEnabled = 0x8000000000000000ULL;
  static constexpr uint64_t kInFlightMask = ~kObservationEnabled;

  static uint64_t loadCount(const uint64_t *count);
  uint64_t conflictCount() const;
  uint64_t failureCount() const;
  bool observing() const;
  void releaseObservation();
  bool beginObservation(uint64_t generation);
  void disableAndDrainObservation();
  template <typename Function>
  static Function previous(void *const *slot,
                           const std::atomic<Function> &runtime);
  static bool hasNominalType(const HeapMetadata *metadata);
  void observeDeallocation(const HeapObject *object,
                           std::atomic<uint64_t> &counter);

  std::mutex install_mutex_;
  std::mutex drain_mutex_;
  std::condition_variable drain_condition_;
  InstallState install_state_ = InstallState::neverAttempted;
  dd_swift_alloc_hook_status_t failure_status_ =
      DD_SWIFT_ALLOC_HOOK_FAILED_REBIND;

  // The enabled bit and callback count share one atomic so stop cannot miss a
  // callback admitted just before it disables observation.
  std::atomic<uint64_t> observation_state_{0};
  // A trampoline can pause in the Swift runtime across stop and restart. Such
  // a call must not enter the replacement observer session when it resumes.
  std::atomic<uint64_t> observation_generation_{0};
  std::atomic<dd_swift_allocation_observer_t> allocation_observer_{nullptr};
  std::atomic<dd_swift_deallocation_observer_t> deallocation_observer_{nullptr};
  std::atomic<AllocFn> runtime_alloc_{nullptr};
  std::atomic<DeallocFn> runtime_class_dealloc_{nullptr};
  std::atomic<PartialClassDeallocFn> runtime_partial_class_dealloc_{nullptr};
  std::atomic<DeallocFn> runtime_object_dealloc_{nullptr};
  std::atomic<GetTypeNameFn> get_type_name_{nullptr};

  // fishhook retains these addresses for future images. The instance must
  // remain alive after stop and until process exit.
  void *first_alloc_ = nullptr;
  void *first_class_dealloc_ = nullptr;
  void *first_partial_class_dealloc_ = nullptr;
  void *first_object_dealloc_ = nullptr;
  uint64_t alloc_patches_ = 0;
  uint64_t class_dealloc_patches_ = 0;
  uint64_t partial_class_dealloc_patches_ = 0;
  uint64_t object_dealloc_patches_ = 0;
  uint64_t alloc_conflicts_ = 0;
  uint64_t class_dealloc_conflicts_ = 0;
  uint64_t partial_class_dealloc_conflicts_ = 0;
  uint64_t object_dealloc_conflicts_ = 0;
  uint64_t alloc_failures_ = 0;
  uint64_t class_dealloc_failures_ = 0;
  uint64_t partial_class_dealloc_failures_ = 0;
  uint64_t object_dealloc_failures_ = 0;

  std::atomic<uint64_t> allocations_{0};
  std::atomic<uint64_t> class_deallocations_{0};
  std::atomic<uint64_t> object_deallocations_{0};
  std::atomic<uint64_t> reentrant_skips_{0};
  static thread_local bool observing_callback_;
};

thread_local bool SwiftAllocHook::observing_callback_ = false;

// Fishhook and observer callbacks are defined after the class implementation.
HeapObject *intercept_alloc(HeapMetadata *, size_t, size_t);
void intercept_class_dealloc(HeapObject *, size_t, size_t);
void intercept_partial_class_dealloc(HeapObject *, const HeapMetadata *, size_t,
                                     size_t);
void intercept_object_dealloc(HeapObject *, size_t, size_t);
dd_swift_class_name_t resolve_class_name(const HeapMetadata *);

uint64_t SwiftAllocHook::loadCount(const uint64_t *count) {
  return __atomic_load_n(count, __ATOMIC_ACQUIRE);
}

uint64_t SwiftAllocHook::conflictCount() const {
  return loadCount(&alloc_conflicts_) + loadCount(&class_dealloc_conflicts_) +
         loadCount(&partial_class_dealloc_conflicts_) +
         loadCount(&object_dealloc_conflicts_);
}

uint64_t SwiftAllocHook::failureCount() const {
  return loadCount(&alloc_failures_) + loadCount(&class_dealloc_failures_) +
         loadCount(&partial_class_dealloc_failures_) +
         loadCount(&object_dealloc_failures_);
}

bool SwiftAllocHook::observing() const {
  return (observation_state_.load(std::memory_order_acquire) &
          kObservationEnabled) != 0 &&
         conflictCount() == 0 && failureCount() == 0;
}

void SwiftAllocHook::releaseObservation() {
  const uint64_t prior =
      observation_state_.fetch_sub(1, std::memory_order_acq_rel);
  if ((prior & kInFlightMask) == 1 && (prior & kObservationEnabled) == 0) {
    std::lock_guard<std::mutex> lock(drain_mutex_);
    drain_condition_.notify_all();
  }
}

bool SwiftAllocHook::beginObservation(uint64_t generation) {
  if ((observation_state_.load(std::memory_order_acquire) &
       kObservationEnabled) == 0) {
    return false;
  }
  const uint64_t prior =
      observation_state_.fetch_add(1, std::memory_order_acq_rel);
  if ((prior & kObservationEnabled) != 0 &&
      observation_generation_.load(std::memory_order_acquire) == generation) {
    return true;
  }
  // Stop or restart changed the observer session before admission.
  releaseObservation();
  return false;
}

// Call only while holding install_mutex_. Start uses the same drain before
// replacing observers, so an admitted callback cannot switch to a new one.
void SwiftAllocHook::disableAndDrainObservation() {
  observation_state_.fetch_and(kInFlightMask, std::memory_order_acq_rel);
  std::unique_lock<std::mutex> lock(drain_mutex_);
  drain_condition_.wait(lock, [this] {
    return (observation_state_.load(std::memory_order_acquire) &
            kInFlightMask) == 0;
  });
}

template <typename Function>
Function SwiftAllocHook::previous(void *const *slot,
                                  const std::atomic<Function> &runtime) {
  void *prior = __atomic_load_n(slot, __ATOMIC_ACQUIRE);
  return prior != nullptr ? reinterpret_cast<Function>(prior)
                          : runtime.load(std::memory_order_acquire);
}

// Swift's heap-local-variable and error-object metadata have no nominal type.
// The first metadata word is a small kind value; class metadata starts with an
// isa pointer. This mirrors the guard exercised in the memory-profiling PoC.
bool SwiftAllocHook::hasNominalType(const HeapMetadata *metadata) {
  if (metadata == nullptr) {
    return false;
  }
  uintptr_t kind = *reinterpret_cast<const uintptr_t *>(metadata);
  return kind < 0x400 || kind >= 0x800;
}

dd_swift_class_name_t
SwiftAllocHook::resolveClassName(const HeapMetadata *metadata) const {
  auto get_name = get_type_name_.load(std::memory_order_acquire);
  if (get_name == nullptr || !hasNominalType(metadata)) {
    return {nullptr, 0};
  }
  SwiftTypeName name = get_name(metadata, false);
  return name.data != nullptr ? dd_swift_class_name_t{name.data, name.length}
                              : dd_swift_class_name_t{nullptr, 0};
}

HeapObject *SwiftAllocHook::interceptAlloc(HeapMetadata *metadata, size_t size,
                                           size_t alignment_mask) {
  const uint64_t generation =
      observation_generation_.load(std::memory_order_acquire);
  AllocFn original = previous(&first_alloc_, runtime_alloc_);
  HeapObject *object = original(metadata, size, alignment_mask);
  if (!observing() || object == nullptr || !hasNominalType(metadata)) {
    return object;
  }
  if (observing_callback_) {
    reentrant_skips_.fetch_add(1, std::memory_order_relaxed);
    return object;
  }
  if (!beginObservation(generation)) {
    return object;
  }

  observing_callback_ = true;
  allocations_.fetch_add(1, std::memory_order_relaxed);
  auto observer = allocation_observer_.load(std::memory_order_acquire);
  if (observer != nullptr) {
    observer(object, static_cast<uint64_t>(size), metadata, resolve_class_name);
  }
  observing_callback_ = false;
  releaseObservation();
  return object;
}

void SwiftAllocHook::observeDeallocation(const HeapObject *object,
                                         std::atomic<uint64_t> &counter) {
  const uint64_t generation =
      observation_generation_.load(std::memory_order_acquire);
  if (!observing() || object == nullptr) {
    return;
  }
  if (observing_callback_) {
    reentrant_skips_.fetch_add(1, std::memory_order_relaxed);
    return;
  }
  if (!beginObservation(generation)) {
    return;
  }

  observing_callback_ = true;
  counter.fetch_add(1, std::memory_order_relaxed);
  auto observer = deallocation_observer_.load(std::memory_order_acquire);
  if (observer != nullptr) {
    // These entry points may run before storage is freed if unowned references
    // remain. Both can report an address, so observers must deduplicate it.
    observer(object);
  }
  observing_callback_ = false;
  releaseObservation();
}

void SwiftAllocHook::interceptClassDealloc(HeapObject *object, size_t size,
                                           size_t alignment_mask) {
  observeDeallocation(object, class_deallocations_);
  DeallocFn original = previous(&first_class_dealloc_, runtime_class_dealloc_);
  original(object, size, alignment_mask);
}

void SwiftAllocHook::interceptPartialClassDealloc(
    HeapObject *object, const HeapMetadata *metadata, size_t size,
    size_t alignment_mask) {
  observeDeallocation(object, class_deallocations_);
  PartialClassDeallocFn original = previous(&first_partial_class_dealloc_,
                                            runtime_partial_class_dealloc_);
  original(object, metadata, size, alignment_mask);
}

void SwiftAllocHook::interceptObjectDealloc(HeapObject *object, size_t size,
                                            size_t alignment_mask) {
  observeDeallocation(object, object_deallocations_);
  DeallocFn original =
      previous(&first_object_dealloc_, runtime_object_dealloc_);
  original(object, size, alignment_mask);
}

dd_swift_alloc_hook_status_t
SwiftAllocHook::start(dd_swift_allocation_observer_t allocation_observer,
                      dd_swift_deallocation_observer_t deallocation_observer) {
  if (allocation_observer == nullptr || deallocation_observer == nullptr) {
    return DD_SWIFT_ALLOC_HOOK_FAILED_INVALID_OBSERVER;
  }

  std::lock_guard<std::mutex> lock(install_mutex_);
  if (install_state_ == InstallState::installed) {
    disableAndDrainObservation();
    if (failureCount() != 0) {
      install_state_ = InstallState::failed;
      failure_status_ = DD_SWIFT_ALLOC_HOOK_FAILED_REBIND;
      return failure_status_;
    }
    if (conflictCount() != 0) {
      install_state_ = InstallState::failed;
      failure_status_ = DD_SWIFT_ALLOC_HOOK_FAILED_CONFLICT;
      return failure_status_;
    }
    allocation_observer_.store(allocation_observer, std::memory_order_release);
    deallocation_observer_.store(deallocation_observer,
                                 std::memory_order_release);
    observation_generation_.fetch_add(1, std::memory_order_acq_rel);
    observation_state_.fetch_or(kObservationEnabled, std::memory_order_release);
    return DD_SWIFT_ALLOC_HOOK_ALREADY_INSTALLED;
  }
  if (install_state_ == InstallState::failed) {
    return failure_status_;
  }

  // Resolve every forward target before any import slot can point at a
  // trampoline. A partial rebind must never make an app call a null pointer.
  void *alloc_symbol = dlsym(RTLD_DEFAULT, "swift_allocObject");
  void *class_dealloc_symbol =
      dlsym(RTLD_DEFAULT, "swift_deallocClassInstance");
  void *partial_class_dealloc_symbol =
      dlsym(RTLD_DEFAULT, "swift_deallocPartialClassInstance");
  void *object_dealloc_symbol = dlsym(RTLD_DEFAULT, "swift_deallocObject");
  auto alloc = reinterpret_cast<AllocFn>(alloc_symbol);
  auto class_dealloc = reinterpret_cast<DeallocFn>(class_dealloc_symbol);
  auto partial_class_dealloc =
      reinterpret_cast<PartialClassDeallocFn>(partial_class_dealloc_symbol);
  auto object_dealloc = reinterpret_cast<DeallocFn>(object_dealloc_symbol);
  auto get_name =
      reinterpret_cast<GetTypeNameFn>(dlsym(RTLD_DEFAULT, "swift_getTypeName"));
  if (alloc == nullptr || class_dealloc == nullptr ||
      partial_class_dealloc == nullptr || object_dealloc == nullptr ||
      get_name == nullptr) {
    return DD_SWIFT_ALLOC_HOOK_FAILED_NO_SYMBOL;
  }
  runtime_alloc_.store(alloc, std::memory_order_release);
  runtime_class_dealloc_.store(class_dealloc, std::memory_order_release);
  runtime_partial_class_dealloc_.store(partial_class_dealloc,
                                       std::memory_order_release);
  runtime_object_dealloc_.store(object_dealloc, std::memory_order_release);
  get_type_name_.store(get_name, std::memory_order_release);

  // first_replaced is published before a slot is patched. fishhook leaves
  // slots with a different previous implementation untouched, because a
  // single trampoline cannot safely forward through two different chains.
  struct rebinding bindings[] = {
      {
          "swift_allocObject",
          reinterpret_cast<void *>(intercept_alloc),
          nullptr,
          &first_alloc_,
          &alloc_patches_,
          &alloc_conflicts_,
          &alloc_failures_,
          alloc_symbol,
      },
      {
          "swift_deallocClassInstance",
          reinterpret_cast<void *>(intercept_class_dealloc),
          nullptr,
          &first_class_dealloc_,
          &class_dealloc_patches_,
          &class_dealloc_conflicts_,
          &class_dealloc_failures_,
          class_dealloc_symbol,
      },
      {
          "swift_deallocPartialClassInstance",
          reinterpret_cast<void *>(intercept_partial_class_dealloc),
          nullptr,
          &first_partial_class_dealloc_,
          &partial_class_dealloc_patches_,
          &partial_class_dealloc_conflicts_,
          &partial_class_dealloc_failures_,
          partial_class_dealloc_symbol,
      },
      {
          "swift_deallocObject",
          reinterpret_cast<void *>(intercept_object_dealloc),
          nullptr,
          &first_object_dealloc_,
          &object_dealloc_patches_,
          &object_dealloc_conflicts_,
          &object_dealloc_failures_,
          object_dealloc_symbol,
      },
  };
  int result = rebind_symbols(bindings, sizeof(bindings) / sizeof(bindings[0]));
  install_state_ =
      InstallState::failed; // fishhook cannot unregister a partial install
  if (result != 0 || failureCount() != 0 || loadCount(&alloc_patches_) == 0 ||
      loadCount(&class_dealloc_patches_) == 0) {
    failure_status_ = DD_SWIFT_ALLOC_HOOK_FAILED_REBIND;
    return DD_SWIFT_ALLOC_HOOK_FAILED_REBIND;
  }
  if (conflictCount() != 0) {
    failure_status_ = DD_SWIFT_ALLOC_HOOK_FAILED_CONFLICT;
    return DD_SWIFT_ALLOC_HOOK_FAILED_CONFLICT;
  }

  allocation_observer_.store(allocation_observer, std::memory_order_release);
  deallocation_observer_.store(deallocation_observer,
                               std::memory_order_release);
  install_state_ = InstallState::installed;
  observation_generation_.fetch_add(1, std::memory_order_acq_rel);
  observation_state_.fetch_or(kObservationEnabled, std::memory_order_release);
  return DD_SWIFT_ALLOC_HOOK_OK;
}

void SwiftAllocHook::stop() {
  // Never restore patched import slots: another rebinder may now own them.
  std::lock_guard<std::mutex> lock(install_mutex_);
  disableAndDrainObservation();
}

dd_swift_alloc_hook_diagnostics_t SwiftAllocHook::diagnostics() const {
  dd_swift_alloc_hook_diagnostics_t result{};
  result.allocations = allocations_.load(std::memory_order_relaxed);
  result.class_deallocations =
      class_deallocations_.load(std::memory_order_relaxed);
  result.object_deallocations =
      object_deallocations_.load(std::memory_order_relaxed);
  result.reentrant_skips = reentrant_skips_.load(std::memory_order_relaxed);
  result.alloc_slots_patched = loadCount(&alloc_patches_);
  result.class_dealloc_slots_patched = loadCount(&class_dealloc_patches_);
  result.object_dealloc_slots_patched = loadCount(&object_dealloc_patches_);
  result.conflicting_slots = conflictCount();
  result.failed_slot_writes = failureCount();
  result.is_enabled = observing();
  return result;
}

// Rebindings persist for the process lifetime. Construct before the first
// rebind, and intentionally never destroy the state used by its trampolines.
SwiftAllocHook &hook() {
  alignas(SwiftAllocHook) static unsigned char storage[sizeof(SwiftAllocHook)];
  static auto *instance = new (storage) SwiftAllocHook();
  return *instance;
}

HeapObject *intercept_alloc(HeapMetadata *metadata, size_t size,
                            size_t alignment_mask) {
  return hook().interceptAlloc(metadata, size, alignment_mask);
}

void intercept_class_dealloc(HeapObject *object, size_t size,
                             size_t alignment_mask) {
  hook().interceptClassDealloc(object, size, alignment_mask);
}

void intercept_partial_class_dealloc(HeapObject *object,
                                     const HeapMetadata *metadata, size_t size,
                                     size_t alignment_mask) {
  hook().interceptPartialClassDealloc(object, metadata, size, alignment_mask);
}

void intercept_object_dealloc(HeapObject *object, size_t size,
                              size_t alignment_mask) {
  hook().interceptObjectDealloc(object, size, alignment_mask);
}

dd_swift_class_name_t resolve_class_name(const HeapMetadata *metadata) {
  return hook().resolveClassName(metadata);
}

} // namespace

extern "C" dd_swift_alloc_hook_status_t dd_swift_alloc_hook_start(
    dd_swift_allocation_observer_t allocation_observer,
    dd_swift_deallocation_observer_t deallocation_observer) {
  return hook().start(allocation_observer, deallocation_observer);
}

extern "C" void dd_swift_alloc_hook_stop(void) { hook().stop(); }

extern "C" dd_swift_alloc_hook_diagnostics_t
dd_swift_alloc_hook_diagnostics(void) {
  return hook().diagnostics();
}

#endif // !TARGET_OS_WATCH
#endif // __APPLE__
