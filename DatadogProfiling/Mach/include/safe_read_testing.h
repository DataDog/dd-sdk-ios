/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_PROFILER_SAFE_READ_TESTING_H_
#define DD_PROFILER_SAFE_READ_TESTING_H_

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Helper to manually re-install handlers if needed by tests.
 */
void init_safe_read_handlers_for_testing(void);

/**
 * Validates the Safe Read mechanism.
 */
bool safe_read_memory_for_testing(void* addr, void* buffer, size_t size);

#ifdef __cplusplus
}
#endif

#endif // DD_PROFILER_SAFE_READ_TESTING_H_
