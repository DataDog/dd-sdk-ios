/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_PROFILER_SAFE_READ_TESTING_H_
#define DD_PROFILER_SAFE_READ_TESTING_H_

#include <stddef.h>
#include <stdint.h>

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#include "dd_profiler.h"  // stack_trace_t

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Reads a contiguous region of the calling task's virtual memory starting at sp
 * into buf (which must be at least buf_size bytes).
 *
 * Mirrors the production read_stack_region used inside stack_trace_sample_thread.
 * Returns the number of contiguous bytes actually read from sp; returns 0 if sp
 * itself is unmapped or invalid.
 */
size_t read_stack_region_for_testing(void* sp, void* buf, size_t buf_size);

/**
 * Walks a frame pointer chain entirely from a pre-populated local buffer.
 *
 * This is the same walk used inside stack_trace_sample_thread, extracted so tests
 * can exercise the bounds-check guards and cycle-termination behavior directly
 * without needing to suspend a real thread or craft live stack memory.
 *
 * @param trace        Pre-allocated trace; trace->frames must point to at least
 *                     max_depth entries. frame_count is reset to 0 on entry.
 * @param initial_fp   First frame pointer to walk from (typically the suspended
 *                     thread's FP register).
 * @param initial_pc   First program counter to record (typically the suspended
 *                     thread's PC register).
 * @param stack_base   Base address that stack_buf was read from (typically SP).
 * @param stack_buf    Buffer containing a snapshot of stack memory.
 * @param bytes_read   Valid bytes in stack_buf.
 * @param max_depth    Hard cap on frames to record.
 */
void walk_frames_in_buffer(
    stack_trace_t* trace,
    void* initial_fp,
    void* initial_pc,
    uintptr_t stack_base,
    const uint8_t* stack_buf,
    size_t bytes_read,
    uint32_t max_depth
);

/**
 * Same as walk_frames_in_buffer, but enables the production safe-read fallback
 * for valid frame pointers that are outside the copied stack buffer.
 *
 * This lets tests verify that large-but-mapped frame gaps do not silently
 * truncate otherwise valid stacks.
 */
void walk_frames_with_safe_read_fallback_for_testing(
    stack_trace_t* trace,
    void* initial_fp,
    void* initial_pc,
    uintptr_t stack_base,
    const uint8_t* stack_buf,
    size_t bytes_read,
    uint32_t max_depth
);

#ifdef __cplusplus
}
#endif

#endif // !TARGET_OS_WATCH
#endif // __APPLE__

#endif // DD_PROFILER_SAFE_READ_TESTING_H_
