#pragma once
#include <stdint.h>

typedef enum {
    E01_ALLOCATION_OK = 0,
    E01_ALLOCATION_ERR_UNSUPPORTED = 1,
    E01_ALLOCATION_ERR_OCCUPIED = 2,
    E01_ALLOCATION_ERR_NOT_INSTALLED = 3,
    E01_ALLOCATION_ERR_NOT_OWNER = 4
} E01AllocationError;

typedef struct { uint64_t operations, requested_bytes; } E01AllocationBucket;
typedef struct {
    E01AllocationBucket process, caller, other;
    uint64_t epoch;
} E01AllocationResult;

typedef struct { E01AllocationError error; int lock_free; } E01AllocationLifecycle;

E01AllocationLifecycle e01_allocation_install(void);
E01AllocationError e01_allocation_uninstall(void);
E01AllocationError e01_allocation_epoch_begin(uint64_t *epoch);
E01AllocationError e01_allocation_epoch_end(uint64_t epoch, E01AllocationResult *result);
int e01_allocation_sentinel(void);
int e01_allocation_caller_calibrate(E01AllocationResult *result);
