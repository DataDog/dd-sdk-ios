/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_PROFILER_BINARY_IMAGE_RESOLVER_H_
#define DD_PROFILER_BINARY_IMAGE_RESOLVER_H_

#include "mach_profiler.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#include <mutex>
#include <unordered_map>
#include <mach-o/dyld.h>

// --- Binary image utility functions ---

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
 * Looks up binary image information for a program counter address.
 *
 * @param[out] info The binary image structure to populate (must be initialized with binary_image_init)
 * @param pc The program counter address to get image info for
 * @return true if binary image was found and info populated, false otherwise
 */
bool binary_image_lookup_pc(binary_image_t* info, void* pc);

// --- Binary image cache ---

namespace dd::profiler {

/**
 * Cached binary image entry with pre-extracted Mach-O metadata.
 */
struct cached_image_t {
    /** Base address where the image is loaded in memory */
    uintptr_t load_address;
    /** UUID of the binary image */
    uuid_t uuid;
    /** Filename of the binary image (owned, null-terminated, or nullptr) */
    char* filename;
};

/**
 * Thread-safe cache for binary image metadata.
 *
 */
class binary_image_cache {
public:
    binary_image_cache();
    ~binary_image_cache();

    // Non-copyable, non-movable
    binary_image_cache(const binary_image_cache&) = delete;
    binary_image_cache& operator=(const binary_image_cache&) = delete;

    /**
     * Populate cache with all currently loaded images and start watching
     * for new image loads via dyld notifications.
     *
     * @return true if dyld register was started successfully, false otherwise
     */
    bool start();

    /**
     * Look up binary image information for a given instruction pointer.
     *
     * @param instruction_ptr The instruction pointer address to resolve
     * @param out_image Output: populated with image info
     * @return true if the image was found, false otherwise
     */
    bool lookup(uint64_t instruction_ptr, binary_image_t* out_image);

    /**
     * Resolve binary image info for all frames in a batch of stack traces.
     *
     * @param traces Array of stack traces whose frames need image info
     * @param count Number of traces in the array
     */
    void resolve_frames(stack_trace_t* traces, size_t count);

    /**
     * Returns the number of cached images.
     */
    size_t size() const;

private:
    mutable std::mutex mutex;
    bool started = false;

    /** Map from image load address → cached image metadata */
    std::unordered_map<uintptr_t, cached_image_t> cache;

    /**
     * Add a single image to the cache from its Mach-O header.
     *
     * @param header The Mach-O header of the image
     * @param name The filesystem path of the image (can be nullptr)
     */
    void add_image_locked(const struct mach_header* header, const char* name);

    /**
     * Static callback registered with _dyld_register_func_for_add_image.
     * Called for each image load (including existing images at registration time).
     */
    static void dyld_add_image_callback(const struct mach_header* mh, intptr_t slide);
};

/**
 * Resolve binary image info for all frames in a batch of stack traces.
 *
 * @param traces Array of stack traces whose frames need image info
 * @param count  Number of traces in the array
 * @param cache  Optional binary image cache (can be nullptr)
 */
void resolve_stack_trace_frames(stack_trace_t* traces, size_t count, binary_image_cache* cache);

} // namespace dd::profiler

#endif // __APPLE__ && !TARGET_OS_WATCH
#endif // DD_PROFILER_BINARY_IMAGE_RESOLVER_H_
