/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_SWIFT_ALLOC_HOOK_TESTING_H_
#define DD_SWIFT_ALLOC_HOOK_TESTING_H_

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#include <stddef.h>

// C ABI aliases let tests call the Swift runtime through their own import
// slots, which fishhook patches. They do not add symbols to the SDK binary.
void *dd_swift_alloc_object_for_testing(const void *metadata, size_t size,
                                        size_t alignment_mask)
    __asm("_swift_allocObject");
void dd_swift_dealloc_uninitialized_object_for_testing(
    void *object, size_t size, size_t alignment_mask)
    __asm("_swift_deallocUninitializedObject");

#endif // !TARGET_OS_WATCH
#endif // __APPLE__
#endif // DD_SWIFT_ALLOC_HOOK_TESTING_H_
