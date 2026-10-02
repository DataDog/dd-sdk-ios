/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_SWIFT_ALLOC_HOOK_H_
#define DD_SWIFT_ALLOC_HOOK_H_

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  const char *data;
  uint64_t length;
} dd_swift_class_name_t;

// Opaque Swift runtime metadata. Only the runtime knows its layout.
typedef struct HeapMetadata HeapMetadata;

/// Invoke the resolver only for sampled allocations. Its result is owned by
/// the Swift runtime; callers must copy the length-delimited bytes if needed.
typedef dd_swift_class_name_t (*dd_swift_class_name_resolver_t)(
    const HeapMetadata *metadata);
typedef void (*dd_swift_allocation_observer_t)(
    const void *address, uint64_t size, const HeapMetadata *metadata,
    dd_swift_class_name_resolver_t resolve_name);
/// Called on entry to a Swift class/object deallocation function. This is
/// not necessarily the storage free: outstanding unowned references can keep
/// a deinitialized object's allocation alive until they are released.
typedef void (*dd_swift_deallocation_observer_t)(const void *address);

typedef enum {
  DD_SWIFT_ALLOC_HOOK_OK = 0,
  DD_SWIFT_ALLOC_HOOK_ALREADY_INSTALLED = 1,
  DD_SWIFT_ALLOC_HOOK_FAILED_NO_SYMBOL = 2,
  DD_SWIFT_ALLOC_HOOK_FAILED_REBIND = 3,
  DD_SWIFT_ALLOC_HOOK_FAILED_CONFLICT = 4,
  DD_SWIFT_ALLOC_HOOK_FAILED_INVALID_OBSERVER = 5
} dd_swift_alloc_hook_status_t;

typedef struct {
  uint64_t allocations;
  uint64_t class_deallocations;
  uint64_t object_deallocations;
  uint64_t reentrant_skips;
  uint64_t alloc_slots_patched;
  uint64_t class_dealloc_slots_patched;
  uint64_t object_dealloc_slots_patched;
  uint64_t conflicting_slots;
  uint64_t failed_slot_writes;
  bool is_enabled;
} dd_swift_alloc_hook_diagnostics_t;

/// Installs process-wide Swift runtime interposition once. The three
/// trampolines are never restored; stop() only disables observation. Replacing
/// observers waits for previously admitted callbacks to finish. A failed
/// install leaves the trampolines forwarding without invoking observers. The
/// defensive swift_deallocObject path is registered even if no loaded image
/// imports it. Do not call start or stop from an observer callback.
dd_swift_alloc_hook_status_t dd_swift_alloc_hook_start(
    dd_swift_allocation_observer_t allocation_observer,
    dd_swift_deallocation_observer_t deallocation_observer);

/// Disables observation and waits for all admitted callbacks to finish.
/// Do not call from an observer callback.
void dd_swift_alloc_hook_stop(void);
dd_swift_alloc_hook_diagnostics_t dd_swift_alloc_hook_diagnostics(void);

#ifdef __cplusplus
}
#endif

#endif // !TARGET_OS_WATCH
#endif // __APPLE__
#endif // DD_SWIFT_ALLOC_HOOK_H_
