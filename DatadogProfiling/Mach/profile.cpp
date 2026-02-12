/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

/**
 * @file profile.cpp
 * @brief Implementation of profiling data aggregation and deduplication
 * 
 * This module implements the core profiling engine that efficiently processes
 * raw stack traces into deduplicated, aggregated profile data.
 * 
 * **Key Implementation Details:**
 * - String interning with hash table lookup for O(1) deduplication
 * - Binary mapping deduplication by load address
 * - Location deduplication by instruction address
 * - UUID formatting for binary identification
 * - System binary detection for filtering
 * 
 * The implementation prioritizes performance for high-throughput profiling
 * workloads while maintaining memory efficiency through aggressive deduplication.
 */

#include "profile.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#include <time.h>

namespace dd::profiler {

/**
 * @brief Calculate uptime to epoch time offset
 *
 * Calculates the offset needed to convert uptime nanoseconds
 * to epoch time in nanoseconds.
 *
 * @return Offset to convert uptime nanoseconds to epoch time
 */
int64_t uptime_epoch_offset() {
    // Get current uptime nanoseconds
    uint64_t uptime_ns = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);

    // Get current epoch time
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    int64_t epoch_time_ns = (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec;

    // Calculate and return offset to convert uptime to epoch
    return epoch_time_ns - (int64_t)uptime_ns;
}

/**
 * @brief Convert binary UUID to formatted string representation
 * 
 * Converts a 16-byte UUID array into the standard hyphenated string format
 * (XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX) for use as build identifiers.
 * 
 * @param uuid 16-byte UUID array
 * @return Formatted UUID string
 */
std::string uuid_string(const uuid_t uuid) {
    char uuid_str[37];  // 36 chars + null terminator
    snprintf(uuid_str, sizeof(uuid_str),
             "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
             uuid[0], uuid[1], uuid[2], uuid[3],
             uuid[4], uuid[5], uuid[6], uuid[7],
             uuid[8], uuid[9], uuid[10], uuid[11],
             uuid[12], uuid[13], uuid[14], uuid[15]);
    return std::string(uuid_str);
}

/**
 * @brief Constructs a new profile aggregator
 * 
 * Initializes the profile with the specified sampling interval and
 * pre-interns commonly used strings for performance optimization.
 * 
 * @param sampling_interval_ns Sampling interval in nanoseconds
 */
profile::profile(uint64_t sampling_interval_ns) 
    : _sampling_interval_ns(sampling_interval_ns)
    , _start_timestamp(0)
    , _end_timestamp(0) {
    
    // Ensure empty string is always at index 0
    _strings.push_back("");
    _string_lookup[""] = 0;
    
    // Pre-intern common strings for performance
    _empty_str_id = intern_string("");
    _wall_time_str_id = intern_string("wall-time");
    _nanoseconds_str_id = intern_string("nanoseconds");
    _end_timestamp_ns_str_id = intern_string("end_timestamp_ns");
    _thread_id_str_id = intern_string("thread id");
    _thread_name_str_id = intern_string("thread name");

    // Initialize epoch offset for uptime conversion
    _epoch_offset = uptime_epoch_offset();
}

/**
 * @brief Convert uptime nanoseconds to epoch time in nanoseconds
 *
 * @param uptime_ns Uptime nanoseconds value
 * @return Epoch time in nanoseconds
 */
int64_t profile::uptime_ns_to_epoch_ns(uint64_t uptime_ns) const {
    return static_cast<int64_t>(uptime_ns) + _epoch_offset;
}

/**
 * @brief Process multiple stack traces into deduplicated samples
 * 
 * Converts raw stack traces into profile samples with automatic deduplication
 * of strings, mappings, and locations. Each trace is processed independently
 * and added to the profile's sample collection.
 * 
 * @param traces Array of stack traces to process
 * @param count Number of traces in the array
 * 
 * **Processing Steps:**
 * 1. Convert stack frames to deduplicated location IDs
 * 2. Create timestamp labels for each sample
 * 3. Store sample values (sampling intervals)
 * 4. Add completed samples to the profile
 */
void profile::add_samples(const stack_trace_t* traces, size_t count) {
    if (!traces) return;
    
    for (int i = 0; i < count; ++i) {
        const auto& trace = traces[i];
        
        // Build location IDs from stack frames
        std::vector<uint32_t> location_ids;
        location_ids.reserve(trace.frame_count);
        for (uint32_t j = 0; j < trace.frame_count; ++j) {
            const auto& frame = trace.frames[j];
            uint32_t location_id = intern_frame(frame);
            location_ids.push_back(location_id);
        }
        
        // Create labels with timestamp, tid, and thread name
        std::vector<label_t> labels;
        labels.reserve(3);
        
        // Add timestamp label (convert uptime nanoseconds to epoch)
        label_t timestamp_label;
        timestamp_label.key_id = _end_timestamp_ns_str_id;
        timestamp_label.str_id = 0;
        timestamp_label.num = uptime_ns_to_epoch_ns(trace.timestamp);
        timestamp_label.num_unit_id = _nanoseconds_str_id;
        labels.push_back(timestamp_label);
        
        // Add thread ID label
        label_t thread_label;
        thread_label.key_id = _thread_id_str_id;
        thread_label.str_id = 0;
        thread_label.num = static_cast<int64_t>(trace.tid);
        thread_label.num_unit_id = 0; // No unit for thread ID
        labels.push_back(thread_label);
        
        // Add thread name label if available
        if (trace.thread_name) {
            label_t thread_name_label;
            thread_name_label.key_id = _thread_name_str_id;
            thread_name_label.str_id = intern_string(trace.thread_name);
            thread_name_label.num = 0;
            thread_name_label.num_unit_id = 0;
            labels.push_back(thread_name_label);
        }
        
        // Create sample
        sample_t sample;
        sample.location_ids = std::move(location_ids);
        sample.labels = std::move(labels);
        sample.values = {static_cast<int64_t>(trace.sampling_interval_nanos)};
        
        _samples.push_back(std::move(sample));

        // Update start/end timestamps
        if (_start_timestamp == 0 || trace.timestamp < _start_timestamp) {
            _start_timestamp = trace.timestamp;
        }

        if (_end_timestamp < trace.timestamp) {
            _end_timestamp = trace.timestamp;
        }
    }
}

/**
 * @brief Deduplicate and intern a string in the string table
 * 
 * Adds the string to the profile's string table if not already present,
 * or returns the existing ID if the string has been seen before.
 * 
 * @param str String to intern
 * @return 0-based index of the string in the string table
 * @note This is the core deduplication mechanism for all string data
 */
uint32_t profile::intern_string(const std::string& str) {
    auto it = _string_lookup.find(str);
    if (it != _string_lookup.end()) return it->second;
    
    uint32_t id = static_cast<uint32_t>(_strings.size());
    _strings.push_back(str);
    _string_lookup[str] = id;
    return id;
}

/**
 * @brief Convert a stack frame to a deduplicated location ID
 * 
 * Processes a single stack frame by first ensuring its binary mapping
 * is registered, then creating a location entry that references the
 * mapping and contains the instruction address.
 * 
 * @param frame Stack frame containing binary info and instruction pointer
 * @return Location ID (1-based) for the frame's instruction address
 */
uint32_t profile::intern_frame(const stack_frame_t& frame) {
    uint32_t mapping_id = intern_binary(frame.image);
    location_t location;
    location.mapping_id = mapping_id;
    location.address = frame.instruction_ptr;
    return intern_location(location);
}

/**
 * @brief Deduplicate and intern a binary mapping
 * 
 * Creates a mapping entry for the binary if not already present,
 * extracting the filename basename and converting UUID to string format.
 * 
 * @param image Binary image information from the runtime
 * @return 1-based mapping ID, or existing ID if mapping already exists
 * @note Uses load address as the primary key for deduplication
 */
uint32_t profile::intern_binary(const binary_image_t& image) {    
    auto it = _mapping_lookup.find(image.load_address);
    if (it != _mapping_lookup.end()) return it->second;

    std::string build_id = uuid_string(image.uuid);
    
    mapping_t mapping;
    mapping.memory_start = image.load_address;
    mapping.filename_id = image.filename ? intern_string(image.filename): 0;
    mapping.build_id = intern_string(build_id);
    
    uint32_t id = static_cast<uint32_t>(_mappings.size() + 1);
    _mappings.push_back(mapping);
    _mapping_lookup[image.load_address] = id;
    return id;
}

/**
 * @brief Deduplicate and intern a code location
 * 
 * Adds the location to the profile's location table if not already present.
 * Locations are deduplicated by instruction address for memory efficiency.
 * 
 * @param location Location data containing mapping ID and address
 * @return 1-based location ID, or existing ID if location already exists
 */
uint32_t profile::intern_location(const location_t& location) {
    auto it = _location_lookup.find(location.address);
    if (it != _location_lookup.end()) return it->second;
    
    uint32_t id = static_cast<uint32_t>(_locations.size() + 1);
    _locations.push_back(location);
    _location_lookup[location.address] = id;
    return id;
}

} // namespace dd::profiler

#endif // __APPLE__ && !TARGET_OS_WATCH

