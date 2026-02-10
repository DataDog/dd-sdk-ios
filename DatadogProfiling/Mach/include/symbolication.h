/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_PROFILER_SYMBOLICATION_H_
#define DD_PROFILER_SYMBOLICATION_H_

#include <stdint.h>
#include <stdbool.h>
#include <uuid/uuid.h>
#include <sys/types.h>

#ifdef __APPLE__

// Address validation constants and macros
//
// These values define the valid range for user-space addresses on 64-bit systems:
//
// MIN_USERSPACE_ADDR (0x1000):
//   - Corresponds to the typical page size (4KB)
//   - Helps avoid null pointer dereference regions (0x0 - 0xFFF)
//
// MAX_USERSPACE_ADDR (0x7FFFFFFFF000ULL):
//   - Upper limit for user-space addresses on 64-bit ARM64/x86_64
//
#ifdef __cplusplus
static constexpr uintptr_t MIN_USERSPACE_ADDR = 0x1000ULL;          // 4KB - avoid null deref region
static constexpr uintptr_t MAX_USERSPACE_ADDR = 0x7FFFFFFFF000ULL;  // ~128TB - max user space on 64-bit

/**
 * Validates if an address is within reasonable user-space bounds.
 * Rejects null pointers, kernel addresses, and other invalid ranges.
 */
static constexpr bool is_valid_userspace_addr(uintptr_t addr) {
    return addr >= MIN_USERSPACE_ADDR && addr <= MAX_USERSPACE_ADDR;
}
#else
#define MIN_USERSPACE_ADDR ((uintptr_t)0x1000ULL)
#define MAX_USERSPACE_ADDR ((uintptr_t)0x7FFFFFFFF000ULL)
#define is_valid_userspace_addr(addr) ((uintptr_t)(addr) >= MIN_USERSPACE_ADDR && (uintptr_t)(addr) <= MAX_USERSPACE_ADDR)
#endif

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Structure representing a binary image loaded in memory.
 */
typedef struct binary_image {
    /** Base address where the image is loaded */
    uint64_t load_address;
    /** UUID of the binary */
    uuid_t uuid;
    /** Filename of the binary */
    const char* filename;
} binary_image_t;

/**
 * Pre-caches binary image information for all currently loaded images.
 */
void profiler_cache_binary_images(void);

/**
 * Initializes a binary image structure to safe defaults.
 */
bool binary_image_init(binary_image_t* info);

/**
 * Destroys a binary image structure.
 */
void binary_image_destroy(binary_image_t* info);

/**
 * Looks up binary image information for a program counter address.
 */
bool binary_image_lookup_pc(binary_image_t* info, void* pc);

#ifdef __cplusplus
}
#endif

#endif // __APPLE__

#endif // DD_PROFILER_SYMBOLICATION_H_
