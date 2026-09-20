#include "E01AllocationCounter.h"
#include <stdatomic.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

typedef void logger_fn(uint32_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uint32_t);
static logger_fn **slot;
static logger_fn *ours;
static pthread_t caller;
static _Atomic uint64_t epoch, ticket, in_flight, process_ops, process_bytes, caller_ops, caller_bytes;
#define E01_EPOCH_STARTING UINT64_MAX
static void *(*volatile e01_malloc)(size_t) = malloc;
static void *(*volatile e01_calloc)(size_t, size_t) = calloc;
static void *(*volatile e01_realloc)(void *, size_t) = realloc;
static _Atomic uintptr_t calibration_sink;
__attribute__((noinline)) static void consume(void *value) { atomic_fetch_xor_explicit(&calibration_sink, (uintptr_t)value, memory_order_relaxed); }

static uint64_t bytes(uint32_t type, uintptr_t a1, uintptr_t a2, uintptr_t a3) {
    return (type & 4) ? a3 : ((type & 8) ? a2 : a1);
}
static void logger(uint32_t type, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t result, uint32_t skip) {
    (void)skip;
    uint64_t current = atomic_load_explicit(&epoch, memory_order_acquire);
    if (!current || current == E01_EPOCH_STARTING || !(type & 2) || !result) return;
    atomic_fetch_add_explicit(&in_flight, 1, memory_order_acquire);
    if (atomic_load_explicit(&epoch, memory_order_acquire) == current) {
        uint64_t requested = bytes(type, a1, a2, a3);
        atomic_fetch_add_explicit(&process_ops, 1, memory_order_relaxed);
        atomic_fetch_add_explicit(&process_bytes, requested, memory_order_relaxed);
        if (pthread_equal(pthread_self(), caller)) {
            atomic_fetch_add_explicit(&caller_ops, 1, memory_order_relaxed);
            atomic_fetch_add_explicit(&caller_bytes, requested, memory_order_relaxed);
        }
    }
    atomic_fetch_sub_explicit(&in_flight, 1, memory_order_release);
}
E01AllocationLifecycle e01_allocation_install(void) {
    E01AllocationLifecycle value = { E01_ALLOCATION_OK, 0 };
    value.lock_free = atomic_is_lock_free(&epoch) && atomic_is_lock_free(&ticket) && atomic_is_lock_free(&in_flight) && atomic_is_lock_free(&process_ops) && atomic_is_lock_free(&process_bytes) && atomic_is_lock_free(&caller_ops) && atomic_is_lock_free(&caller_bytes);
    if (!value.lock_free) { value.error = E01_ALLOCATION_ERR_UNSUPPORTED; return value; }
    slot = (logger_fn **)dlsym(RTLD_DEFAULT, "malloc_logger");
    if (!slot) { value.error = E01_ALLOCATION_ERR_UNSUPPORTED; return value; }
    if (*slot) { value.error = E01_ALLOCATION_ERR_OCCUPIED; return value; }
    caller = pthread_self(); ours = logger; *slot = ours; return value;
}
E01AllocationError e01_allocation_uninstall(void) {
    if (!slot) return E01_ALLOCATION_ERR_NOT_INSTALLED;
    if (atomic_load_explicit(&epoch, memory_order_acquire)) return E01_ALLOCATION_ERR_OCCUPIED;
    while (atomic_load_explicit(&in_flight, memory_order_acquire)) {}
    if (*slot != ours) return E01_ALLOCATION_ERR_NOT_OWNER;
    *slot = NULL; slot = NULL; ours = NULL; return E01_ALLOCATION_OK;
}
E01AllocationError e01_allocation_epoch_begin(uint64_t *out) {
    if (!out) return E01_ALLOCATION_ERR_NOT_OWNER;
    if (!slot || *slot != ours) return E01_ALLOCATION_ERR_NOT_INSTALLED;
    uint64_t none = 0;
    if (!atomic_compare_exchange_strong_explicit(&epoch, &none, E01_EPOCH_STARTING, memory_order_acq_rel, memory_order_acquire)) return E01_ALLOCATION_ERR_OCCUPIED;
    while (atomic_load_explicit(&in_flight, memory_order_acquire)) {}
    atomic_store(&process_ops, 0); atomic_store(&process_bytes, 0); atomic_store(&caller_ops, 0); atomic_store(&caller_bytes, 0);
    uint64_t next = atomic_fetch_add_explicit(&ticket, 1, memory_order_relaxed) + 1;
    if (!next || next == E01_EPOCH_STARTING) next = atomic_fetch_add_explicit(&ticket, 1, memory_order_relaxed) + 1;
    atomic_store_explicit(&epoch, next, memory_order_release);
    *out = next; return E01_ALLOCATION_OK;
}
E01AllocationError e01_allocation_epoch_end(uint64_t expected, E01AllocationResult *out) {
    if (!expected || expected == E01_EPOCH_STARTING || !out) return E01_ALLOCATION_ERR_NOT_OWNER;
    if (!atomic_compare_exchange_strong_explicit(&epoch, &expected, 0, memory_order_acq_rel, memory_order_acquire)) return E01_ALLOCATION_ERR_NOT_OWNER;
    while (atomic_load_explicit(&in_flight, memory_order_acquire)) {}
    out->process.operations = atomic_load(&process_ops); out->process.requested_bytes = atomic_load(&process_bytes);
    out->caller.operations = atomic_load(&caller_ops); out->caller.requested_bytes = atomic_load(&caller_bytes);
    out->other.operations = out->process.operations - out->caller.operations;
    out->other.requested_bytes = out->process.requested_bytes - out->caller.requested_bytes; out->epoch = expected;
    return E01_ALLOCATION_OK;
}
int e01_allocation_sentinel(void) {
    void *a = e01_malloc(17), *b = e01_calloc(3, 19);
    void *resized = a ? e01_realloc(a, 91) : NULL;
    if (resized) consume(resized);
    if (b) consume(b);
    free(resized ? resized : a); free(b);
    return a && b && resized;
}
int e01_allocation_caller_calibrate(E01AllocationResult *out) {
    if (!out) return 0;
    uint64_t e; if (e01_allocation_epoch_begin(&e)) return 0;
    int sentinel_ok = e01_allocation_sentinel();
    return sentinel_ok && !e01_allocation_epoch_end(e, out) && out->caller.operations == 3 && out->caller.requested_bytes == 165;
}
