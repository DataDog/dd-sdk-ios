/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#ifndef DD_PROFILER_PROFILE_PACKER_H_
#define DD_PROFILER_PROFILE_PACKER_H_

#ifdef __APPLE__
#include <TargetConditionals.h>
#if !TARGET_OS_WATCH

#include <cstdint>
#include <cstddef>

namespace dd::profiler {

class profile;

/**
 * Pack profile data into pprof protobuf binary format (wall-time variant)
 *
 * Converts internal profile data structures to the standardized pprof
 * protobuf format for serialization and consumption by profiling tools.
 * Emits a single wall-time/nanoseconds sample type.
 *
 * @param prof The profile data to pack
 * @param data Output buffer pointer - allocated buffer containing serialized data
 * @return Size of serialized data in bytes, or 0 on failure
 *
 * @note The caller is responsible for freeing the returned buffer with free()
 * @note This function is thread-safe and does not modify the input profile
 */
size_t profile_pprof_pack(const profile& prof, uint8_t** data);

/**
 * Pack profile data into pprof protobuf binary format (heap variant)
 *
 * Emits four sample types in Go-aligned order:
 *   alloc_objects/count, alloc_space/bytes, inuse_objects/count, inuse_space/bytes
 *
 * The period_type is space/bytes and the period is the profile's sampling_interval_ns()
 * value (expected to be 524288 bytes for a standard heap profile).
 *
 * Each sample's values vector must contain exactly four entries in the same order
 * as the sample types above.
 *
 * @param prof The profile data to pack
 * @param data Output buffer pointer - allocated buffer containing serialized data
 * @return Size of serialized data in bytes, or 0 on failure
 *
 * @note The caller is responsible for freeing the returned buffer with free()
 * @note This function is thread-safe and does not modify the input profile
 */
size_t profile_pprof_pack_heap(const profile& prof, uint8_t** data);

} // namespace dd::profiler

#endif // !TARGET_OS_WATCH
#endif // __APPLE__

#endif // DD_PROFILER_PROFILE_PACKER_H_
