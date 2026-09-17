/* Test-fixture-only heap instrumentation. Never linked into the SDK product.
 * ABI source: apple-oss-distributions/libmalloc src/malloc.c (malloc_logger).
 * Record successful allocation operations on this thread only, including realloc.
 */
#include "AllocationCounter.h"
#include <dlfcn.h>
#include <malloc/malloc.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

typedef void logger_fn(uint32_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uint32_t);
static pthread_t workload_thread;
static int counting;
static uint64_t allocations;
static uint64_t bytes;
static void logger(uint32_t type, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t result, uint32_t skip) {
    (void)skip;
    if (pthread_self() != workload_thread || !counting || !(type & 2) || !result) return;
    allocations++;
    bytes += (type & 4) ? a3 : ((type & 8) ? a2 : a1);
}
int baseline_allocation_counter_install(void) {
    logger_fn **slot = (logger_fn **)dlsym(RTLD_DEFAULT, "malloc_logger");
    if (!slot || *slot) return 0;
    workload_thread = pthread_self();
    *slot = logger;
    return 1;
}
void baseline_allocation_begin(void) { allocations = 0; bytes = 0; counting = 1; }
void baseline_allocation_end(void) { counting = 0; }
uint64_t baseline_allocation_count(void) { return allocations; }
uint64_t baseline_allocation_bytes(void) { return bytes; }
__attribute__((noinline,optnone)) int baseline_allocation_calibrate(void) {
    baseline_allocation_begin();
    void *a = malloc(17);
    void *b = calloc(3, 19);
    a = realloc(a, 91);
    memset(a, 1, 91);
    memset(b, 2, 57);
    free(a); free(b);
    baseline_allocation_end();
    return allocations == 3 && bytes == 165;
}
uint64_t baseline_live_heap_bytes(void) {
    malloc_statistics_t statistics = {0};
    malloc_zone_statistics(NULL, &statistics);
    return statistics.size_in_use;
}
