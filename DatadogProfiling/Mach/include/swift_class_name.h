/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_SWIFT_CLASS_NAME_H_
#define DD_SWIFT_CLASS_NAME_H_

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

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

#ifdef __cplusplus
}
#endif

#endif // !TARGET_OS_WATCH
#endif // __APPLE__
#endif // DD_SWIFT_CLASS_NAME_H_
