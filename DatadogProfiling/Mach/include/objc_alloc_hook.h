/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_OBJC_ALLOC_HOOK_H_
#define DD_OBJC_ALLOC_HOOK_H_

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// The observer owns any sampled live-set state. Class names are borrowed
/// runtime strings and must be copied if retained beyond the class lifetime.
typedef void (*dd_objc_allocation_observer_t)(
    const void *address, uint64_t size, const char *class_name);
/// The receiver is already tearing down. Treat it only as an address.
typedef void (*dd_objc_deallocation_observer_t)(const void *address);

typedef enum {
  DD_OBJC_ALLOC_HOOK_OK = 0,
  DD_OBJC_ALLOC_HOOK_ALREADY_INSTALLED = 1,
  DD_OBJC_ALLOC_HOOK_FAILED_NO_METHOD = 2,
  DD_OBJC_ALLOC_HOOK_FAILED_INSTALL = 3,
  DD_OBJC_ALLOC_HOOK_FAILED_INVALID_OBSERVER = 4
} dd_objc_alloc_hook_status_t;

typedef struct {
  uint64_t allocations;
  uint64_t deallocations;
  uint64_t reentrant_skips;
  /// These flags record that each trampoline was installed once. They do not
  /// prove that the current swizzle chain still reaches it.
  bool alloc_installed;
  bool dealloc_installed;
  /// A different current IMP may be an outer swizzle that forwards to Datadog,
  /// or a replacement that bypasses Datadog entirely.
  bool has_outer_alloc_hook;
  bool has_outer_dealloc_hook;
  bool is_enabled;
} dd_objc_alloc_hook_diagnostics_t;

/// Installs process-wide NSObject allocation/deallocation trampolines. A class
/// whose +allocWithZone: override does not call through NSObject's
/// implementation is not observed on allocation, even if its deallocation
/// reaches this hook. Allocation observers run after forwarding; deallocation
/// observers run before forwarding and must treat the receiver only as an
/// address.
/// An incomplete install leaves any installed trampoline forwarding with
/// observation disabled; a later call may finish the installation. Neither
/// trampoline is removed on stop because another swizzle may depend on it.
/// If an earlier swizzle later restores its saved IMP, it can remove a Datadog
/// trampoline from the active chain. A later start still treats that trampoline
/// as installed and may report observation enabled without receiving callbacks.
/// Allocation and deallocation interception can be lost independently. The
/// current IMP alone cannot distinguish this from an outer swizzle that still
/// forwards to Datadog, so the hook cannot safely reinstall automatically.
/// Replacing observers waits for admitted callbacks to finish. A rejected
/// start leaves an active observer pair unchanged. Do not call start or stop
/// from an observer callback.
dd_objc_alloc_hook_status_t dd_objc_alloc_hook_start(
    dd_objc_allocation_observer_t allocation_observer,
    dd_objc_deallocation_observer_t deallocation_observer);

/// Disables observation and waits for admitted callbacks to finish.
/// Do not call from an observer callback.
void dd_objc_alloc_hook_stop(void);
dd_objc_alloc_hook_diagnostics_t dd_objc_alloc_hook_diagnostics(void);

#ifdef __cplusplus
}
#endif

#endif // !TARGET_OS_WATCH
#endif // __APPLE__
#endif // DD_OBJC_ALLOC_HOOK_H_
