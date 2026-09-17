#include <stdint.h>
int baseline_allocation_counter_install(void);
void baseline_allocation_begin(void);
void baseline_allocation_end(void);
uint64_t baseline_allocation_count(void);
uint64_t baseline_allocation_bytes(void);
int baseline_allocation_calibrate(void);
uint64_t baseline_live_heap_bytes(void);
