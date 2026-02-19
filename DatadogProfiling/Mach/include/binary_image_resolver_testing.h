/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_PROFILER_BINARY_IMAGE_RESOLVER_TESTING_H_
#define DD_PROFILER_BINARY_IMAGE_RESOLVER_TESTING_H_

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#include "dd_profiler.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Initializes a binary image structure to safe defaults.
 *
 * @param[out] info The binary image structure to initialize
 * @return true if initialization succeeded, false on null pointer
 */
bool binary_image_init(binary_image_t* info);

/**
 * Destroys a binary image structure, freeing any memory allocated by that struct
 * but not the image struct itself.
 *
 * @param info The binary image structure to destroy
 */
void binary_image_destroy(binary_image_t* info);

/**
 * Looks up binary image information for a program counter address by parsing
 * the Mach-O header via dladdr. This does not use any cache and performs a full
 * lookup every time.
 *
 * @param[out] info The binary image structure to populate (must be initialized with binary_image_init)
 * @param pc The program counter address to get image info for
 * @return true if binary image was found and info populated, false otherwise
 */
bool binary_image_lookup_pc(binary_image_t* info, void* pc);

#ifdef __cplusplus
}
#endif

#endif // !TARGET_OS_WATCH
#endif // __APPLE__

#endif // DD_PROFILER_BINARY_IMAGE_RESOLVER_TESTING_H_
