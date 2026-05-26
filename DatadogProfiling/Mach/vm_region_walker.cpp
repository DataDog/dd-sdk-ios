/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "vm_region_walker.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#include <mach/mach.h>
#include <mach/task_info.h>
#include <mach/vm_map.h>
#include <mach/vm_region.h>
#include <mach/vm_statistics.h>
#include <mach/mach_time.h>
#include <cstring>

// =====================================================================
// VM Region Walker (RUM-16460, POC Question #4)
//
// Walks the process VM address space using vm_region_recurse_64 and
// classifies each region by user_tag into category buckets. The walk
// is the standard mechanism used by Apple's vmmap(1) and leaks(1)
// command-line tools, so the API surface is well-trodden public ground.
//
// IMPORTANT App Store safety finding (RUM-16460):
//   <mach/mach_vm.h> is `#error unsupported` on the iOS device SDK.
//   The mach_vm_* family (mach_vm_region_recurse, mach_vm_allocate,
//   mach_vm_address_t) is NOT available on iOS. Only the vm_*_64
//   family from <mach/vm_map.h> is. We use vm_region_recurse_64 here.
//
// References:
//   <mach/vm_map.h> public header (iOS-safe)
//   <mach/vm_statistics.h> for VM_MEMORY_* tags
//   xnu sources: osfmk/vm/vm_region.c
// =====================================================================

/// Translates a high-resolution Mach timebase tick to nanoseconds.
/// Cached after first use; the timebase is constant per process.
static uint64_t mach_ticks_to_nanos(uint64_t ticks) {
    static mach_timebase_info_data_t info = {};
    if (info.denom == 0) {
        mach_timebase_info(&info);
    }
    return (ticks * info.numer) / info.denom;
}

/// Aggregates one VM region's footprint into the right category bucket.
static void accumulate_region(dd_vm_category_t* category,
                              uint64_t virtual_bytes,
                              uint64_t resident_bytes,
                              uint64_t dirty_bytes) {
    category->virtual_bytes += virtual_bytes;
    category->resident_bytes += resident_bytes;
    category->dirty_bytes += dirty_bytes;
    category->region_count += 1;
}

/// Selects the right category bucket for a given region.
///
/// Tag values are from <mach/vm_statistics.h>; the bucket boundaries are
/// aligned with how vmmap groups regions in its summary view.
///
/// `external_pager` is set when a region is file-backed (e.g. an mmap'd
/// file or a dylib's __TEXT segment). For untagged regions we use that
/// signal to route them to mapped_files instead of "other".
static dd_vm_category_t* category_for_region(dd_vm_snapshot_t* snapshot,
                                             int user_tag,
                                             bool external_pager) {
    // Allocator-owned regions cover the bulk of "managed" memory.
    // Includes tcmalloc since it's also a userland allocator; treating
    // it as managed avoids a misleading split for apps that use it.
    if (user_tag == VM_MEMORY_MALLOC
        || user_tag == VM_MEMORY_MALLOC_SMALL
        || user_tag == VM_MEMORY_MALLOC_LARGE
        || user_tag == VM_MEMORY_MALLOC_HUGE
        || user_tag == VM_MEMORY_SBRK
        || user_tag == VM_MEMORY_REALLOC
        || user_tag == VM_MEMORY_MALLOC_TINY
        || user_tag == VM_MEMORY_MALLOC_LARGE_REUSABLE
        || user_tag == VM_MEMORY_MALLOC_LARGE_REUSED
        || user_tag == VM_MEMORY_MALLOC_NANO
        || user_tag == VM_MEMORY_MALLOC_MEDIUM
        || user_tag == VM_MEMORY_MALLOC_PROB_GUARD
        || user_tag == VM_MEMORY_TCMALLOC
        || user_tag == VM_MEMORY_DYLD_MALLOC) {
        return &snapshot->managed_heap;
    }
    if (user_tag == VM_MEMORY_STACK) {
        return &snapshot->stacks;
    }
    // SHARED_PMAP is the shared library text mapping. DYLD is dyld's own
    // bookkeeping. Both belong with dylibs from the user's perspective.
    if (user_tag == VM_MEMORY_DYLIB
        || user_tag == VM_MEMORY_SHARED_PMAP
        || user_tag == VM_MEMORY_DYLD) {
        return &snapshot->dylibs;
    }
    if (user_tag == VM_MEMORY_JAVASCRIPT_CORE
        || user_tag == VM_MEMORY_JAVASCRIPT_JIT_EXECUTABLE_ALLOCATOR
        || user_tag == VM_MEMORY_JAVASCRIPT_JIT_REGISTER_FILE) {
        return &snapshot->jit_code;
    }
    // Untagged file-backed regions are mmap'd files (Core Data, image
    // assets, framework resources). The user_tag is zero because the
    // region wasn't allocated through the malloc family.
    if (external_pager) {
        return &snapshot->mapped_files;
    }
    return &snapshot->other;
}

/// Fills the process-level totals from task_info(TASK_VM_INFO).
/// phys_footprint is the field iOS uses for jetsam decisions, so it
/// anchors the breakdown numerically.
static void fill_task_totals(dd_vm_snapshot_t* snapshot) {
    task_vm_info_data_t vm_info = {};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    const kern_return_t kr = task_info(mach_task_self(),
                                       TASK_VM_INFO,
                                       reinterpret_cast<task_info_t>(&vm_info),
                                       &count);
    if (kr != KERN_SUCCESS) {
        return;
    }
    snapshot->phys_footprint = vm_info.phys_footprint;
    snapshot->resident_size = vm_info.resident_size;
    snapshot->virtual_size = vm_info.virtual_size;
}

extern "C" dd_vm_snapshot_t dd_vm_walk_regions(void) {
    dd_vm_snapshot_t snapshot = {};
    const uint64_t start_ticks = mach_absolute_time();

    fill_task_totals(&snapshot);

    vm_address_t address = 0;
    natural_t depth = 0;

    while (true) {
        vm_size_t region_size = 0;
        vm_region_submap_info_data_64_t info = {};
        mach_msg_type_number_t info_count = VM_REGION_SUBMAP_INFO_COUNT_64;

        const kern_return_t kr = vm_region_recurse_64(mach_task_self(),
                                                      &address,
                                                      &region_size,
                                                      &depth,
                                                        reinterpret_cast<vm_region_recurse_info_t>(&info),
                                                        &info_count);
        if (kr != KERN_SUCCESS) {
            // KERN_INVALID_ADDRESS is the normal end of iteration when
            // we walk past the last region in the address space.
            break;
        }

        // Recurse into submaps rather than treating the submap entry itself
        // as one big region. This matches what vmmap does, and prevents
        // double-counting (the kernel reports the submap once at the
        // outer depth and then again at the inner depth).
        if (info.is_submap) {
            depth += 1;
            continue;
        }

        // Resident size = pages currently in RAM for this region.
        // Per-page size is fixed at 4 KB on Apple platforms today
        // (16 KB on some hardware, but the kernel still returns the
        // 4 KB-page-count in `pages_resident`).
        const uint64_t resident_bytes = static_cast<uint64_t>(info.pages_resident)
                                        * static_cast<uint64_t>(vm_kernel_page_size);
        const uint64_t dirty_bytes = static_cast<uint64_t>(info.pages_dirtied)
                                     * static_cast<uint64_t>(vm_kernel_page_size);

        dd_vm_category_t* category = category_for_region(&snapshot,
                                                         info.user_tag,
                                                         info.external_pager != 0);
        accumulate_region(category,
                          static_cast<uint64_t>(region_size),
                          resident_bytes,
                          dirty_bytes);

        snapshot.total_regions += 1;
        address += region_size;
    }

    snapshot.walk_duration_ns = mach_ticks_to_nanos(mach_absolute_time() - start_ticks);
    return snapshot;
}

#endif // defined(__APPLE__) && !TARGET_OS_WATCH
