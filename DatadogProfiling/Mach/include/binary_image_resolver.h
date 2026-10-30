/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_PROFILER_BINARY_IMAGE_RESOLVER_H_
#define DD_PROFILER_BINARY_IMAGE_RESOLVER_H_

#include "dd_profiler.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#include <mutex>
#include <memory>
#include <unordered_map>
#include <mach-o/dyld.h>

// --- Binary image utility functions ---

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

// --- Binary image cache ---

#ifdef __cplusplus

namespace dd::profiler {

/**
 * Cached binary image entry with pre-extracted Mach-O metadata.
 */
struct cached_image_t {
    /** Base address where the image is loaded in memory */
    uintptr_t load_address;
    /** UUID of the binary image */
    uuid_t uuid;
    /** Null-terminated filename borrowed from cache-owned storage, or nullptr */
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
    binary_image_cache(binary_image_cache&&) = delete;
    binary_image_cache& operator=(binary_image_cache&&) = delete;

    /**
     * Populate cache with all currently loaded images and start watching
     * for new image loads via dyld notifications. Only one cache may watch
     * dyld; another instance returns false. Use shared_binary_image_cache()
     * for production consumers.
     *
     * @return true if images were loaded successfully, false otherwise
     */
    bool load();

    /**
     * Look up binary image information for a given instruction pointer.
     *
     * @param instruction_ptr The instruction pointer address to resolve
     * @param out_image Output: populated with image info. The filename is
     * borrowed from this cache and must not be passed to binary_image_destroy().
     * @return true if the image was found, false otherwise
     */
    bool lookup(uint64_t instruction_ptr, binary_image_t* out_image);

    /**
     * Add or refresh an image at its load address. Replaced filenames remain
     * valid for borrowers until this cache is destroyed. NULL headers are ignored.
     */
    void add_image(const struct mach_header* header, const char* name);

    /**
     * Look up an already cached image by load address. Clears out_image on a
     * miss; returned filenames borrow cache storage until its destruction.
     */
    bool lookup_image(uintptr_t load_address, binary_image_t* out_image);

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

    /// Simulates failure of the next filename ownership allocation on this cache.
    void fail_next_filename_allocation_for_testing();

private:
    mutable std::mutex mutex;
    bool started = false;

    /** Map from image load address → cached image metadata */
    std::unordered_map<uintptr_t, cached_image_t> cache;

    struct filename_storage;

    /** Every published filename remains owned until this cache is destroyed. */
    std::unique_ptr<filename_storage> filenames;
    bool fail_next_filename_allocation = false;

    /** Takes ownership of a malloc buffer, freeing it on admission failure. */
    char* retain_filename_locked(char* filename);

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
 * Returns the process-wide image cache shared by CPU and heap profiling, or
 * nullptr if initialization fails. Acquire outside allocation/deallocation
 * observers and Mach thread suspension. Initialization and dyld registration
 * happen once, independently of either profiler's start/stop lifecycle.
 *
 * The cache intentionally lives until process exit: dyld has no unregister
 * operation, and cached filenames must survive CPU profiler teardown while
 * a heap encoder still uses them. Consumers borrow the pointer and must not
 * delete it. Per-profile mapping/location IDs remain owned by each encoder.
 */
binary_image_cache* shared_binary_image_cache();

/**
 * Resolve binary image info for all frames in a batch of stack traces.
 *
 * @param traces Array of stack traces whose frames need image info
 * @param count  Number of traces in the array
 * @param cache  Optional binary image cache (can be nullptr)
 */
void resolve_stack_trace_frames(stack_trace_t* traces, size_t count, binary_image_cache* cache);

} // namespace dd::profiler

#endif // __cplusplus

#endif // __APPLE__ && !TARGET_OS_WATCH
#endif // DD_PROFILER_BINARY_IMAGE_RESOLVER_H_
