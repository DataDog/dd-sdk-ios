/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "symbolication.h"

#ifdef __APPLE__

#include <dlfcn.h>
#include <mach-o/loader.h>
#include <mach-o/dyld.h>
#include <algorithm>
#include <mutex>
#include <vector>
#include <string.h>
#include <stdlib.h>

struct library_image_t {
    uintptr_t start_addr;
    uintptr_t end_addr;
    binary_image_t info;
};

static std::vector<library_image_t> g_image_libraries;
static std::mutex g_image_libraries_mutex;

// Mach-O validation constants
//
// MAX_LOAD_COMMANDS (1000):
//   - Reasonable upper bound for number of load commands in a Mach-O file
//   - Typical executables have 20-50 load commands, complex ones may have ~100
//   - 1000 is a generous safety limit to catch corrupted/malicious headers
//
// MAX_LOAD_COMMAND_SIZE (0x10000 = 64KB):
//   - Maximum size for a single load command
//   - Most load commands are < 1KB, largest (like LC_CODE_SIGNATURE) rarely exceed 16KB
//
static const uint32_t MAX_LOAD_COMMANDS = 1000;         // Generous upper bound for ncmds
static const uint32_t MAX_LOAD_COMMAND_SIZE = 0x10000;  // 64KB max per load command

/**
 * Validates if the number of load commands in a Mach-O header is reasonable.
 */
static inline bool is_valid_load_command_count(uint32_t ncmds) {
    return ncmds > 0 && ncmds <= MAX_LOAD_COMMANDS;
}

/**
 * Validates if a load command size is within acceptable bounds.
 */
static inline bool is_valid_load_command_size(uint32_t cmdsize) {
    return cmdsize >= sizeof(struct load_command) && cmdsize <= MAX_LOAD_COMMAND_SIZE;
}

extern "C" {

/**
 * Initializes a binary image structure to safe defaults.
 *
 * @param[out] info The binary image structure to initialize
 * @return true if initialization succeeded, false on null pointer
 */
bool binary_image_init(binary_image_t* info) {
    if (!info) return false;
    memset(info->uuid, 0, sizeof(uuid_t));
    info->load_address = 0;
    info->filename = nullptr;
    return true;
}

/**
 * Destroys a binary image structure, freeing any memory allocated by that struct
 * but not the image struct itself.
 *
 * @param info The binary image structure to destroy
 */
void binary_image_destroy(binary_image_t* info) {
    if (!info) return;
    
    if (info->filename) {
        free((void*)info->filename);
        info->filename = nullptr;
    }
    memset(info->uuid, 0, sizeof(uuid_t));
    info->load_address = 0;
}

/**
 * Looks up binary image information for a program counter address.
 *
 * @param[out] info The binary image structure to populate (must be initialized with binary_image_init)
 * @param pc The program counter address to get image info for
 * @return true if binary image was found and info populated, false otherwise
 */
bool binary_image_lookup_pc(binary_image_t* info, void* pc) {
    if (!info) return false;
    
    // Validate the PC address - it should be a reasonable user-space address
    uintptr_t addr = (uintptr_t)pc;
    if (!is_valid_userspace_addr(addr)) return false;

    // Try cache first
    {
        std::lock_guard<std::mutex> lock(g_image_libraries_mutex);
        if (!g_image_libraries.empty()) {
            auto it = std::upper_bound(g_image_libraries.begin(), g_image_libraries.end(), addr,
                [](uintptr_t val, const library_image_t& entry) {
                    return val < entry.start_addr;
                });
            
            if (it != g_image_libraries.begin()) {
                --it;
                if (addr >= it->start_addr && addr < it->end_addr) {
                    info->load_address = it->info.load_address;
                    memcpy(info->uuid, it->info.uuid, sizeof(uuid_t));
                    if (it->info.filename) {
                        info->filename = strdup(it->info.filename);
                    }
                    return true;
                }
            }
        }
    }
    
    // Fallback for libraries loaded after cache or if cache is empty
    Dl_info dl_info;
    if (dladdr(pc, &dl_info) == 0) return false;
    if (!is_valid_userspace_addr((uintptr_t)dl_info.dli_fbase)) return false;

    // Copy filename if available
    if (dl_info.dli_fname) {
        size_t fname_len = strlen(dl_info.dli_fname) + 1;
        char* fname = (char*)malloc(fname_len);
        if (fname) {
            strcpy(fname, dl_info.dli_fname);
            info->filename = fname;
        }
    }

    // Get UUID from the image
    const struct mach_header_64* header = (const struct mach_header_64*)dl_info.dli_fbase;
    if (!header || header->magic != MH_MAGIC_64) return false;
    // Validate ncmds to prevent reading too far
    if (!is_valid_load_command_count(header->ncmds)) return false;

    const struct load_command* cmd = (const struct load_command*)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; ++i) {
        // Validate command size to prevent buffer overruns
        if (!is_valid_load_command_size(cmd->cmdsize)) break;
        
        if (cmd->cmd == LC_UUID) {
            const struct uuid_command* uuid_cmd = (const struct uuid_command*)cmd;
            if (cmd->cmdsize >= sizeof(struct uuid_command)) {
                memcpy(info->uuid, uuid_cmd->uuid, sizeof(uuid_t));
                info->load_address = (uintptr_t)dl_info.dli_fbase;
                return true;
            }
        }
        cmd = (const struct load_command*)((char*)cmd + cmd->cmdsize);
    }

    return false;
}

void profiler_cache_binary_images(void) {
    std::lock_guard<std::mutex> lock(g_image_libraries_mutex);
    if (!g_image_libraries.empty()) return;

    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header_64* header = (const struct mach_header_64*)_dyld_get_image_header(i);
        if (!header || header->magic != MH_MAGIC_64) continue;

        uintptr_t slide = _dyld_get_image_vmaddr_slide(i);
        uintptr_t low_addr = UINTPTR_MAX;
        uintptr_t high_addr = 0;
        uuid_t uuid = {0};
        bool found_uuid = false;

        const struct load_command* cmd = (const struct load_command*)(header + 1);
        for (uint32_t j = 0; j < header->ncmds; j++) {
            if (cmd->cmd == LC_SEGMENT_64) {
                const struct segment_command_64* seg = (const struct segment_command_64*)cmd;
                uintptr_t seg_start = slide + seg->vmaddr;
                uintptr_t seg_end = seg_start + seg->vmsize;
                if (seg_start < low_addr) low_addr = seg_start;
                if (seg_end > high_addr) high_addr = seg_end;
            } else if (cmd->cmd == LC_UUID) {
                const struct uuid_command* uuid_cmd = (const struct uuid_command*)cmd;
                memcpy(uuid, uuid_cmd->uuid, sizeof(uuid_t));
                found_uuid = true;
            }
            cmd = (const struct load_command*)((char*)cmd + cmd->cmdsize);
        }

        if (found_uuid && low_addr != UINTPTR_MAX) {
            library_image_t entry;
            binary_image_init(&entry.info);
            entry.start_addr = low_addr;
            entry.end_addr = high_addr;
            entry.info.load_address = (uint64_t)header;
            memcpy(entry.info.uuid, uuid, sizeof(uuid_t));
            const char* name = _dyld_get_image_name(i);
            if (name) entry.info.filename = strdup(name);
            g_image_libraries.push_back(entry);
        }
    }

    std::sort(g_image_libraries.begin(), g_image_libraries.end(), [](const library_image_t& a, const library_image_t& b) {
        return a.start_addr < b.start_addr;
    });
}

} // extern "C"

#endif // __APPLE__
