/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "binary_image_resolver.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#include <dlfcn.h>
#include <string.h>
#include <stdlib.h>
#include <mach-o/loader.h>

// Address validation constants
//
// MIN_USERSPACE_ADDR (0x1000):
//   Corresponds to the typical page size (4KB). Avoids null pointer
//   dereference regions (0x0 - 0xFFF).
//
// MAX_USERSPACE_ADDR (0x7FFFFFFFF000ULL):
//   Upper limit for user-space addresses on 64-bit ARM64/x86_64.

static constexpr uintptr_t MIN_USERSPACE_ADDR = 0x1000ULL;
static constexpr uintptr_t MAX_USERSPACE_ADDR = 0x7FFFFFFFF000ULL;

// Mach-O validation constants
//
// MAX_LOAD_COMMANDS (1000):
//   Generous upper bound. Typical executables have 20-50 load commands.
//
// MAX_LOAD_COMMAND_SIZE (0x10000 = 64KB):
//   Maximum size for a single load command. Most are < 1KB.

static constexpr uint32_t MAX_LOAD_COMMANDS = 1000;
static constexpr uint32_t MAX_LOAD_COMMAND_SIZE = 0x10000;

/**
 * Validates if an address is within reasonable user-space bounds.
 * Rejects null pointers, kernel addresses, and other invalid ranges.
 */
static constexpr bool is_valid_userspace_addr(uintptr_t addr) {
    return addr >= MIN_USERSPACE_ADDR && addr <= MAX_USERSPACE_ADDR;
}

/**
 * Validates if the number of load commands in a Mach-O header is reasonable.
 * Rejects empty files and suspiciously large command counts.
 */
static constexpr bool is_valid_load_command_count(uint32_t ncmds) {
    return ncmds > 0 && ncmds <= MAX_LOAD_COMMANDS;
}

/**
 * Validates if a load command size is within acceptable bounds.
 * Prevents buffer overruns from malformed command sizes.
 */
static constexpr bool is_valid_load_command_size(uint32_t cmdsize) {
    return cmdsize >= sizeof(struct load_command) && cmdsize <= MAX_LOAD_COMMAND_SIZE;
}

/**
 * g_cacheptr_mutex protects the g_binary_image_cache pointer so that the
 * dyld callback and the destructor do not race on the pointer itself.
 * The instance mutex (binary_image_cache::mutex) protects the cache map.
 */
static std::mutex g_cacheptr_mutex;
static dd::profiler::binary_image_cache* g_binary_image_cache = nullptr;

// ============================================================================
// Binary image utility functions
// ============================================================================

bool binary_image_init(binary_image_t* info) {
    if (!info) return false;
    memset(info->uuid, 0, sizeof(uuid_t));
    info->load_address = 0;
    info->filename = nullptr;
    return true;
}

void binary_image_destroy(binary_image_t* info) {
    if (!info) return;

    if (info->filename) {
        free((void*)info->filename);
        info->filename = nullptr;
    }
    memset(info->uuid, 0, sizeof(uuid_t));
    info->load_address = 0;
}

bool binary_image_lookup_pc(binary_image_t* info, void* pc) {
    if (!info) return false;

    // Validate the PC address
    if (!is_valid_userspace_addr((uintptr_t)pc)) return false;

    Dl_info dl_info;
    if (dladdr(pc, &dl_info) == 0) return false;
    if (!is_valid_userspace_addr((uintptr_t)dl_info.dli_fbase)) return false;

    // Get UUID from the Mach-O header
    const struct mach_header_64* header = (const struct mach_header_64*)dl_info.dli_fbase;
    // Only support 64-bit images
    if (!header || header->magic != MH_MAGIC_64) return false;
    if (!is_valid_load_command_count(header->ncmds)) return false;

    bool found_uuid = false;
    const struct load_command* cmd = (const struct load_command*)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; ++i) {
        if (!is_valid_load_command_size(cmd->cmdsize)) break;

        if (cmd->cmd == LC_UUID) {
            const struct uuid_command* uuid_cmd = (const struct uuid_command*)cmd;
            if (cmd->cmdsize >= sizeof(struct uuid_command)) {
                memcpy(info->uuid, uuid_cmd->uuid, sizeof(uuid_t));
                info->load_address = (uintptr_t)dl_info.dli_fbase;
                found_uuid = true;
            }
            break;
        }
        cmd = (const struct load_command*)((char*)cmd + cmd->cmdsize);
    }

    if (!found_uuid) return false;

    // Copy filename if available. We still consider lookup successful
    // even if allocation fails; UUID + load address are enough to map.
    if (dl_info.dli_fname) {
        size_t fname_len = strlen(dl_info.dli_fname) + 1;
        char* fname = (char*)malloc(fname_len);
        if (fname) {
            memcpy(fname, dl_info.dli_fname, fname_len);
            info->filename = fname;
        }
    }

    return true;
}

// ============================================================================
// Binary image cache
// ============================================================================

namespace dd::profiler {

binary_image_cache::binary_image_cache() = default;

binary_image_cache::~binary_image_cache() {
    // Null the global pointer so late dyld callbacks become no-ops.
    {
        std::lock_guard<std::mutex> glock(g_cacheptr_mutex);
        if (g_binary_image_cache == this) {
            g_binary_image_cache = nullptr;
        }
    }

    // No more dyld callbacks will reference this instance.
    // Clean up cached data.
    for (auto& pair : cache) {
        if (pair.second.filename) {
            free(pair.second.filename);
        }
    }
    cache.clear();
}

bool binary_image_cache::start() {
    {
        std::lock_guard<std::mutex> glock(g_cacheptr_mutex);
        if (started) return started;
        started = true;
        g_binary_image_cache = this;
    }

    // _dyld_register_func_for_add_image synchronously calls back for
    // all already-loaded images (populating the cache), then calls back
    // asynchronously on the loading thread when new images are loaded.
    _dyld_register_func_for_add_image(dyld_add_image_callback);
    return started;
}

void binary_image_cache::dyld_add_image_callback(const struct mach_header* mh, intptr_t slide) {
    // Acquire global pointer mutex to safely read g_binary_image_cache.
    std::lock_guard<std::mutex> glock(g_cacheptr_mutex);
    if (!g_binary_image_cache || !mh) return;

    // Get image name via dladdr on the header pointer itself.
    Dl_info dl_info;
    const char* name = nullptr;
    if (dladdr(mh, &dl_info)) {
        name = dl_info.dli_fname;
    }

    // Lock the instance mutex to modify the cache map.
    std::lock_guard<std::mutex> ilock(g_binary_image_cache->mutex);
    g_binary_image_cache->add_image_locked(mh, name);
}

void binary_image_cache::add_image_locked(const struct mach_header* header, const char* name) {
    if (!header) return;

    // Only support 64-bit images
    if (header->magic != MH_MAGIC_64) return;

    const struct mach_header_64* header64 = (const struct mach_header_64*)header;
    uintptr_t load_address = (uintptr_t)header;

    // Skip if already cached
    if (cache.find(load_address) != cache.end()) return;

    // Validate load commands
    if (!is_valid_load_command_count(header64->ncmds)) return;

    // Initialize cached entry
    cached_image_t cached;
    cached.load_address = load_address;
    memset(cached.uuid, 0, sizeof(uuid_t));
    cached.filename = nullptr;

    // Copy filename
    if (name) {
        size_t len = strlen(name) + 1;
        cached.filename = (char*)malloc(len);
        if (cached.filename) {
            memcpy(cached.filename, name, len);
        }
    }

    // Find UUID in load commands
    const struct load_command* cmd = (const struct load_command*)(header64 + 1);
    for (uint32_t i = 0; i < header64->ncmds; ++i) {
        if (!is_valid_load_command_size(cmd->cmdsize)) break;

        if (cmd->cmd == LC_UUID) {
            const struct uuid_command* uuid_cmd = (const struct uuid_command*)cmd;
            if (cmd->cmdsize >= sizeof(struct uuid_command)) {
                memcpy(cached.uuid, uuid_cmd->uuid, sizeof(uuid_t));
            }
            break;
        }
        cmd = (const struct load_command*)((char*)cmd + cmd->cmdsize);
    }

    cache.emplace(load_address, cached);
}

bool binary_image_cache::lookup(uint64_t instruction_ptr, binary_image_t* out_image) {
    if (!out_image) return false;
    binary_image_init(out_image);

    // Use dladdr to find which image contains this instruction pointer.
    Dl_info dl_info;
    if (dladdr((void*)instruction_ptr, &dl_info) == 0) return false;

    uintptr_t load_address = (uintptr_t)dl_info.dli_fbase;

    {
        std::lock_guard<std::mutex> lock(mutex);
        auto it = cache.find(load_address);
        if (it != cache.end()) {
            // Cache hit — copy cached data to output
            const cached_image_t& cached = it->second;
            out_image->load_address = cached.load_address;
            memcpy(out_image->uuid, cached.uuid, sizeof(uuid_t));

            if (cached.filename) {
                size_t len = strlen(cached.filename) + 1;
                char* fname = (char*)malloc(len);
                if (fname) {
                    memcpy(fname, cached.filename, len);
                    out_image->filename = fname;
                }
            }
            return true;
        }
    }

    // Cache miss — fall back to full Mach-O header parsing.
    // This handles images loaded between start() and now, or images
    // that the dyld callback missed.
    if (binary_image_lookup_pc(out_image, (void*)instruction_ptr)) {
        // Cache the result for future lookups
        cached_image_t cached;
        cached.load_address = out_image->load_address;
        memcpy(cached.uuid, out_image->uuid, sizeof(uuid_t));
        cached.filename = nullptr;

        if (out_image->filename) {
            size_t len = strlen(out_image->filename) + 1;
            cached.filename = (char*)malloc(len);
            if (cached.filename) {
                memcpy(cached.filename, out_image->filename, len);
            }
        }

        std::lock_guard<std::mutex> lock(mutex);
        bool inserted = cache.emplace(cached.load_address, cached).second;
        if (!inserted && cached.filename) {
            // Another thread inserted this image first (e.g., dyld callback).
            // Free the duplicate filename we allocated.
            free(cached.filename);
        }
        return true;
    }

    return false;
}

void binary_image_cache::resolve_frames(stack_trace_t* traces, size_t count) {
    for (size_t i = 0; i < count; i++) {
        for (uint32_t j = 0; j < traces[i].frame_count; j++) {
            auto& frame = traces[i].frames[j];
            binary_image_init(&frame.image);
            lookup(frame.instruction_ptr, &frame.image);
        }
    }
}

size_t binary_image_cache::size() const {
    std::lock_guard<std::mutex> lock(mutex);
    return cache.size();
}

void resolve_stack_trace_frames(stack_trace_t* traces, size_t count, binary_image_cache* cache) {
    if (cache) {
        cache->resolve_frames(traces, count);
    } else {
        for (size_t i = 0; i < count; i++) {
            for (uint32_t j = 0; j < traces[i].frame_count; j++) {
                auto& frame = traces[i].frames[j];
                binary_image_init(&frame.image);
                binary_image_lookup_pc(&frame.image, (void*)frame.instruction_ptr);
            }
        }
    }
}

} // namespace dd::profiler

#endif // __APPLE__ && !TARGET_OS_WATCH
