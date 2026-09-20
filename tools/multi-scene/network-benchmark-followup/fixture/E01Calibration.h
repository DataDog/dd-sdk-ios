#pragma once
#include "E01AllocationCounter.h"
#include <dispatch/dispatch.h>
int e01_calibrate_queue(dispatch_queue_t queue, E01AllocationResult *out);
int e01_calibrate_concurrent(E01AllocationResult *out);
uint64_t e01_live_heap_bytes(void);
