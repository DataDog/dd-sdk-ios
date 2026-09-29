/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "objc_alloc_hook.h"

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#if DEBUG
#include "objc_alloc_hook_testing.h"
#endif

#include <atomic>
#include <condition_variable>
#include <malloc/malloc.h>
#include <mutex>
#include <new>
#include <objc/runtime.h>

namespace {

// NSZone is an opaque pointer in this ABI. Keep the trampoline in plain C++.
using AllocFn = id (*)(Class, SEL, void *);
using DeallocFn = void (*)(id, SEL);

class ObjCAllocHook {
public:
  ObjCAllocHook() = default;
  ~ObjCAllocHook() = default;
  ObjCAllocHook(const ObjCAllocHook &) = delete;
  ObjCAllocHook &operator=(const ObjCAllocHook &) = delete;
  ObjCAllocHook(ObjCAllocHook &&) = delete;
  ObjCAllocHook &operator=(ObjCAllocHook &&) = delete;

  dd_objc_alloc_hook_status_t
  start(dd_objc_allocation_observer_t allocation_observer,
        dd_objc_deallocation_observer_t deallocation_observer);
  void stop();
  dd_objc_alloc_hook_diagnostics_t diagnostics() const;
  id interceptAlloc(Class cls, SEL selector, void *zone);
  void interceptDealloc(id object, SEL selector);
#if DEBUG
  void failAfterAllocOnce();
#endif

private:
  static constexpr uint64_t kObservationEnabled = 0x8000000000000000ULL;
  static constexpr uint64_t kInFlightMask = ~kObservationEnabled;

  bool observationEnabled() const;
  void endObservation();
  bool beginObservation(uint64_t generation);
  void disableAndDrainObservation();

  std::mutex install_mutex_;
  std::mutex drain_mutex_;
  std::condition_variable drain_condition_;
  std::atomic<uint64_t> observation_state_{0};
  std::atomic<uint64_t> observation_generation_{0};
  std::atomic<bool> alloc_installed_{false};
  std::atomic<bool> dealloc_installed_{false};
  std::atomic<AllocFn> previous_alloc_{nullptr};
  std::atomic<DeallocFn> previous_dealloc_{nullptr};
  std::atomic<dd_objc_allocation_observer_t> allocation_observer_{nullptr};
  std::atomic<dd_objc_deallocation_observer_t> deallocation_observer_{nullptr};
  std::atomic<uint64_t> allocations_{0};
  std::atomic<uint64_t> deallocations_{0};
  std::atomic<uint64_t> reentrant_skips_{0};
  bool unrecoverable_install_failure_ = false;
#if DEBUG
  std::atomic<bool> fail_after_alloc_once_{false};
#endif
  std::atomic<Method> alloc_method_{nullptr};
  std::atomic<Method> dealloc_method_{nullptr};
  inline static thread_local bool observing_callback_ = false;
};

ObjCAllocHook &hook();
id intercept_alloc(Class cls, SEL selector, void *zone);
void intercept_dealloc(id object, SEL selector);

bool ObjCAllocHook::observationEnabled() const {
  return (observation_state_.load(std::memory_order_acquire) &
          kObservationEnabled) != 0;
}

void ObjCAllocHook::endObservation() {
  const uint64_t prior =
      observation_state_.fetch_sub(1, std::memory_order_acq_rel);
  if ((prior & kInFlightMask) == 1 &&
      (prior & kObservationEnabled) == 0) {
    std::lock_guard<std::mutex> lock(drain_mutex_);
    drain_condition_.notify_all();
  }
}

bool ObjCAllocHook::beginObservation(uint64_t generation) {
  if (!observationEnabled()) {
    return false;
  }
  const uint64_t prior =
      observation_state_.fetch_add(1, std::memory_order_acq_rel);
  if ((prior & kObservationEnabled) != 0 &&
      observation_generation_.load(std::memory_order_acquire) == generation) {
    return true;
  }
  endObservation();
  return false;
}

// Call while holding install_mutex_ so observers cannot be replaced until
// every callback admitted to the previous session has finished.
void ObjCAllocHook::disableAndDrainObservation() {
  observation_state_.fetch_and(kInFlightMask, std::memory_order_acq_rel);
  std::unique_lock<std::mutex> lock(drain_mutex_);
  drain_condition_.wait(lock, [this] {
    return (observation_state_.load(std::memory_order_acquire) &
            kInFlightMask) == 0;
  });
}

// A block-backed override can allocate while observing these hot paths and
// re-enter them. Use C-callable IMPs to avoid that and per-call block overhead.
// Publish the forwarding target before replacing either method so an in-flight
// call can always forward.
id ObjCAllocHook::interceptAlloc(Class cls, SEL selector, void *zone) {
  const uint64_t generation =
      observation_generation_.load(std::memory_order_acquire);
  const AllocFn previous = previous_alloc_.load(std::memory_order_acquire);
  id object = previous != nullptr ? previous(cls, selector, zone) : nil;
  if (object == nil || !beginObservation(generation)) {
    return object;
  }
  if (observing_callback_) {
    reentrant_skips_.fetch_add(1, std::memory_order_relaxed);
    endObservation();
    return object;
  }

  observing_callback_ = true;
  const size_t allocated_size = malloc_size(object);
  const size_t size = allocated_size != 0
                          ? allocated_size
                          : class_getInstanceSize(cls);
  const char *name = class_getName(cls);
  const auto observer = allocation_observer_.load(std::memory_order_acquire);
  if (observer != nullptr) {
    observer(object, static_cast<uint64_t>(size), name);
    allocations_.fetch_add(1, std::memory_order_relaxed);
  }
  observing_callback_ = false;
  endObservation();
  return object;
}

void ObjCAllocHook::interceptDealloc(id object, SEL selector) {
  const uint64_t generation =
      observation_generation_.load(std::memory_order_acquire);
  // Do not send any Objective-C message to object here. Its subclass may
  // already have destroyed its ivars. The observer receives its address only.
  if (object != nil && beginObservation(generation)) {
    if (observing_callback_) {
      reentrant_skips_.fetch_add(1, std::memory_order_relaxed);
    } else {
      observing_callback_ = true;
      const auto observer =
          deallocation_observer_.load(std::memory_order_acquire);
      if (observer != nullptr) {
        observer(object);
        deallocations_.fetch_add(1, std::memory_order_relaxed);
      }
      observing_callback_ = false;
    }
    endObservation();
  }

  const DeallocFn previous =
      previous_dealloc_.load(std::memory_order_acquire);
  if (previous != nullptr) {
    previous(object, selector);
  }
}

dd_objc_alloc_hook_status_t ObjCAllocHook::start(
    dd_objc_allocation_observer_t allocation_observer,
    dd_objc_deallocation_observer_t deallocation_observer) {
  std::lock_guard<std::mutex> lock(install_mutex_);
  if (allocation_observer == nullptr || deallocation_observer == nullptr) {
    return DD_OBJC_ALLOC_HOOK_FAILED_INVALID_OBSERVER;
  }
  if (unrecoverable_install_failure_) {
    return DD_OBJC_ALLOC_HOOK_FAILED_INSTALL;
  }

  // Installation state is historical. A third-party restoration can remove
  // our trampoline while these flags remain true; see objc_alloc_hook.h.
  const bool already_installed =
      alloc_installed_.load(std::memory_order_acquire) &&
      dealloc_installed_.load(std::memory_order_acquire);
  if (!already_installed) {
    Class nsobject = objc_getClass("NSObject");
    if (nsobject == Nil) {
      return DD_OBJC_ALLOC_HOOK_FAILED_NO_METHOD;
    }
    const SEL alloc_selector = sel_registerName("allocWithZone:");
    const SEL dealloc_selector = sel_registerName("dealloc");
    Method alloc_method = class_getClassMethod(nsobject, alloc_selector);
    Method dealloc_method = class_getInstanceMethod(nsobject, dealloc_selector);
    if (alloc_method == nullptr || dealloc_method == nullptr) {
      return DD_OBJC_ALLOC_HOOK_FAILED_NO_METHOD;
    }
    alloc_method_.store(alloc_method, std::memory_order_release);
    dealloc_method_.store(dealloc_method, std::memory_order_release);

    // Preflight both forwarding targets before modifying either method.
    const IMP current_alloc = method_getImplementation(alloc_method);
    const IMP current_dealloc = method_getImplementation(dealloc_method);
    if (current_alloc == nullptr || current_dealloc == nullptr) {
      return DD_OBJC_ALLOC_HOOK_FAILED_NO_METHOD;
    }
    if ((!alloc_installed_.load(std::memory_order_acquire) &&
         current_alloc == reinterpret_cast<IMP>(intercept_alloc)) ||
        (!dealloc_installed_.load(std::memory_order_acquire) &&
         current_dealloc == reinterpret_cast<IMP>(intercept_dealloc))) {
      unrecoverable_install_failure_ = true;
      return DD_OBJC_ALLOC_HOOK_FAILED_INSTALL;
    }

    if (!alloc_installed_.load(std::memory_order_acquire)) {
      previous_alloc_.store(
          reinterpret_cast<AllocFn>(current_alloc),
          std::memory_order_release);
      IMP previous = method_setImplementation(
          alloc_method, reinterpret_cast<IMP>(intercept_alloc));
      if (previous == nullptr ||
          previous == reinterpret_cast<IMP>(intercept_alloc)) {
        // The runtime may already have installed our IMP. Retrying could
        // capture that trampoline as its own forward target and recurse.
        unrecoverable_install_failure_ = true;
        return DD_OBJC_ALLOC_HOOK_FAILED_INSTALL;
      }
      previous_alloc_.store(reinterpret_cast<AllocFn>(previous),
                            std::memory_order_release);
      alloc_installed_.store(true, std::memory_order_release);
    }

#if DEBUG
    if (fail_after_alloc_once_.exchange(false, std::memory_order_acq_rel)) {
      return DD_OBJC_ALLOC_HOOK_FAILED_INSTALL;
    }
#endif

    if (!dealloc_installed_.load(std::memory_order_acquire)) {
      previous_dealloc_.store(
          reinterpret_cast<DeallocFn>(current_dealloc),
          std::memory_order_release);
      IMP previous = method_setImplementation(
          dealloc_method, reinterpret_cast<IMP>(intercept_dealloc));
      if (previous == nullptr ||
          previous == reinterpret_cast<IMP>(intercept_dealloc)) {
        unrecoverable_install_failure_ = true;
        return DD_OBJC_ALLOC_HOOK_FAILED_INSTALL;
      }
      previous_dealloc_.store(reinterpret_cast<DeallocFn>(previous),
                              std::memory_order_release);
      dealloc_installed_.store(true, std::memory_order_release);
    }
  }

  disableAndDrainObservation();
  allocation_observer_.store(allocation_observer, std::memory_order_release);
  deallocation_observer_.store(deallocation_observer,
                               std::memory_order_release);
  observation_generation_.fetch_add(1, std::memory_order_acq_rel);
  observation_state_.fetch_or(kObservationEnabled,
                              std::memory_order_release);
  return already_installed ? DD_OBJC_ALLOC_HOOK_ALREADY_INSTALLED
                           : DD_OBJC_ALLOC_HOOK_OK;
}

void ObjCAllocHook::stop() {
  // Never restore either IMP: an outer layer can retain our trampoline as its
  // forwarding target, and an inner layer may have since been disabled.
  std::lock_guard<std::mutex> lock(install_mutex_);
  disableAndDrainObservation();
}

dd_objc_alloc_hook_diagnostics_t ObjCAllocHook::diagnostics() const {
  dd_objc_alloc_hook_diagnostics_t result{};
  result.allocations = allocations_.load(std::memory_order_relaxed);
  result.deallocations = deallocations_.load(std::memory_order_relaxed);
  result.reentrant_skips = reentrant_skips_.load(std::memory_order_relaxed);
  result.alloc_installed = alloc_installed_.load(std::memory_order_acquire);
  result.dealloc_installed = dealloc_installed_.load(std::memory_order_acquire);
  result.is_enabled = observationEnabled();
  const Method alloc_method = alloc_method_.load(std::memory_order_acquire);
  const Method dealloc_method = dealloc_method_.load(std::memory_order_acquire);
  result.has_outer_alloc_hook =
      result.alloc_installed && alloc_method != nullptr &&
      method_getImplementation(alloc_method) !=
          reinterpret_cast<IMP>(intercept_alloc);
  result.has_outer_dealloc_hook =
      result.dealloc_installed && dealloc_method != nullptr &&
      method_getImplementation(dealloc_method) !=
          reinterpret_cast<IMP>(intercept_dealloc);
  return result;
}

#if DEBUG
void ObjCAllocHook::failAfterAllocOnce() {
  fail_after_alloc_once_.store(true, std::memory_order_release);
}
#endif

// Trampolines remain installed for the process lifetime. Construct the state
// before replacing either IMP and never destroy it at shutdown.
ObjCAllocHook &hook() {
  alignas(ObjCAllocHook) static unsigned char storage[sizeof(ObjCAllocHook)];
  static auto *instance = new (storage) ObjCAllocHook();
  return *instance;
}

id intercept_alloc(Class cls, SEL selector, void *zone) {
  return hook().interceptAlloc(cls, selector, zone);
}

void intercept_dealloc(id object, SEL selector) {
  hook().interceptDealloc(object, selector);
}

} // namespace

extern "C" dd_objc_alloc_hook_status_t dd_objc_alloc_hook_start(
    dd_objc_allocation_observer_t allocation_observer,
    dd_objc_deallocation_observer_t deallocation_observer) {
  return hook().start(allocation_observer, deallocation_observer);
}

extern "C" void dd_objc_alloc_hook_stop(void) { hook().stop(); }

extern "C" dd_objc_alloc_hook_diagnostics_t
dd_objc_alloc_hook_diagnostics(void) {
  return hook().diagnostics();
}

#if DEBUG
extern "C" void dd_objc_alloc_hook_test_fail_after_alloc_once(void) {
  hook().failAfterAllocOnce();
}
#endif

#endif // !TARGET_OS_WATCH
#endif // __APPLE__
