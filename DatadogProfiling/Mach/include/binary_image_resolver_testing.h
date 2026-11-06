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
#include <mach-o/loader.h>

#ifdef __cplusplus
#include "binary_image_resolver.h"
typedef dd::profiler::binary_image_cache binary_image_cache_testing_t;
extern "C" {
#else
typedef struct binary_image_cache_testing binary_image_cache_testing_t;
#endif

#ifndef __cplusplus
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
#endif

/// Isolated cache without dyld registration. Destroy only handles created here,
/// after all readers have finished using their borrowed filenames.
binary_image_cache_testing_t* binary_image_cache_create_for_testing(void);
void binary_image_cache_destroy_for_testing(binary_image_cache_testing_t* cache);

/// Borrowed process-wide cache; must not be destroyed by tests.
binary_image_cache_testing_t* binary_image_cache_shared_for_testing(void);

/// Thin adapters for exercising the real C++ cache from Swift tests. Lookups
/// return borrowed filenames that must not be passed to binary_image_destroy().
void binary_image_cache_add_image_for_testing(
    binary_image_cache_testing_t* cache, const void* header, const char* name);
bool binary_image_cache_lookup_for_testing(
    binary_image_cache_testing_t* cache, uint64_t pc, binary_image_t* image);
bool binary_image_cache_lookup_image_for_testing(
    binary_image_cache_testing_t* cache, uintptr_t load_address, binary_image_t* image);
size_t binary_image_cache_size_for_testing(binary_image_cache_testing_t* cache);

/// Fails the next filename ownership allocation on this isolated cache.
void binary_image_cache_fail_next_filename_allocation_for_testing(binary_image_cache_testing_t* cache);

#ifdef __cplusplus
}
#endif

#endif // !TARGET_OS_WATCH
#endif // __APPLE__

#endif // DD_PROFILER_BINARY_IMAGE_RESOLVER_TESTING_H_
