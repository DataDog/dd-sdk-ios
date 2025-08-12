/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

/**
 * @file profile.h
 * @brief Core profiling data structures and aggregation engine
 * 
 * This module provides efficient data structures for collecting, deduplicating,
 * and aggregating profiling samples. The design optimizes for:
 * 
 * - Memory efficiency through string/mapping/location deduplication
 * - Fast sample ingestion with O(1) lookups for existing entities
 * - Clean separation from serialization concerns
 * 
 * The profile class serves as the main aggregation engine that processes
 * raw stack traces and converts them into a deduplicated, efficient format
 * suitable for serialization to pprof format.
 */

#ifndef DD_PROFILER_PROFILE_H_
#define DD_PROFILER_PROFILE_H_

#include "mach_profiler.h"
#include <string>
#include <unordered_map>
#include <vector>
#include <cstdint>

namespace dd::profiler {

/**
 * @brief Convert binary UUID to formatted string representation
 * @param uuid 16-byte UUID array
 * @return Formatted UUID string in standard hyphenated format
 */
std::string uuid_string(const uuid_t uuid);

/**
 * @brief Represents a deduplicated binary mapping in the profile
 * 
 * Maps a contiguous region of memory to a binary file. Each mapping
 * corresponds to a loaded binary (executable, library, etc.) and contains
 * the information needed to symbolicate addresses within that region.
 * 
 * All strings are deduplicated and stored as IDs referencing the profile's
 * string table for memory efficiency.
 */
struct mapping_t {
    uint64_t memory_start;
    uint32_t filename_id;
    uint32_t build_id;
};

/**
 * @brief Represents a deduplicated code location in the profile
 * 
 * A location corresponds to a specific instruction address within a binary
 * mapping. Locations are deduplicated across samples to minimize memory usage
 * and enable efficient aggregation of samples from the same code location.
 * 
 * @note The address is an offset within the mapping, not an absolute memory address
 */
struct location_t {
    uint32_t mapping_id;
    uint64_t address;
};

/**
 * @brief Key-value metadata attached to profiling samples
 * 
 * Labels provide additional context for samples, such as timestamps,
 * thread IDs, or custom application metadata. They support both string
 * and numeric values with optional units.
 * 
 * String values are deduplicated and stored as IDs referencing the
 * profile's string table for memory efficiency.
 */
struct label_t {
    uint32_t key_id;
    uint32_t str_id;
    int64_t num;
    uint32_t num_unit_id;
};

/**
 * @brief Individual profiling sample with stack trace and metadata
 * 
 * Represents a single profiling sample containing:
 * - Stack trace as a sequence of location IDs (leaf-to-root order)
 * - Associated labels (e.g., timestamps, thread info)
 * - Sample values (e.g., CPU time, wall time, memory allocation)
 * - Timestamp when the sample was collected
 * 
 * Samples are not aggregated at this level - aggregation happens during
 * serialization if needed.
 */
struct sample_t {
    std::vector<uint32_t> location_ids;
    std::vector<label_t> labels;
    std::vector<int64_t> values;
    uint64_t timestamp;
};

/**
 * @brief Efficient profiling data aggregator with automatic deduplication
 * 
 * The profile class is the core engine for processing profiling data. It provides:
 * 
 * **Key Features:**
 * - String deduplication with O(1) lookup via hash table
 * - Binary mapping deduplication by memory address
 * - Code location deduplication by instruction address  
 * - Fast sample ingestion from stack traces
 * - Memory-efficient storage optimized for large datasets
 * 
 * **Thread Safety:**
 * - Not thread-safe by design for performance
 * - Callers must ensure external synchronization if needed
 * 
 * **Usage Pattern:**
 * 1. Create profile with sampling interval
 * 2. Call add_samples() with stack traces
 * 3. Use external serializer (e.g., profile_pprof_pack) for output
 * 
 * The class maintains internal deduplication tables and exposes the
 * deduplicated data through public member variables for serialization.
 */
class profile {
public:
    /**
     * @brief Construct a new profile aggregator
     * @param sampling_interval_ns Sampling interval in nanoseconds
     */
    explicit profile(uint64_t sampling_interval_ns);
    ~profile() = default;
    
    profile(const profile&) = delete;
    profile& operator=(const profile&) = delete;
    
    /**
     * @brief Process multiple stack traces into deduplicated samples
     * @param traces Array of stack traces to process
     * @param count Number of traces in the array
     */
    void add_samples(const stack_trace_t* traces, size_t count);

    /** @brief Get read-only access to deduplicated string table */
    const std::vector<std::string>& strings() const { return _strings; }
    
    /** @brief Get read-only access to deduplicated binary mappings */
    const std::vector<mapping_t>& mappings() const { return _mappings; }
    
    /** @brief Get read-only access to deduplicated code locations */
    const std::vector<location_t>& locations() const { return _locations; }
    
    /** @brief Get read-only access to collected samples */
    const std::vector<sample_t>& samples() const { return _samples; }
    
    /** @brief Get profile sampling interval in nanoseconds */
    uint64_t sampling_interval_ns() const { return _sampling_interval_ns; }
    
    /** @brief Get cached string ID for empty string */
    uint32_t empty_str_id() const { return _empty_str_id; }
    
    /** @brief Get cached string ID for "wall-time" */
    uint32_t wall_time_str_id() const { return _wall_time_str_id; }
    
    /** @brief Get cached string ID for "nanoseconds" */
    uint32_t nanoseconds_str_id() const { return _nanoseconds_str_id; }
    
    /** @brief Get cached string ID for "end_timestamp_ns" */
    uint32_t end_timestamp_ns_str_id() const { return _end_timestamp_ns_str_id; }
    
    /** @brief Get cached string ID for "tid" */
    uint32_t tid_str_id() const { return _tid_str_id; }

private:
    /** @brief Deduplicated string table (index 0 is always empty string) */
    std::vector<std::string> _strings;
    
    /** @brief Deduplicated binary mappings (1-based IDs) */
    std::vector<mapping_t> _mappings;
    
    /** @brief Deduplicated code locations (1-based IDs) */
    std::vector<location_t> _locations;
    
    /** @brief All collected samples */
    std::vector<sample_t> _samples;
    
    /** @brief Profile sampling interval in nanoseconds */
    uint64_t _sampling_interval_ns;
    
    /** @brief Cached string ID for empty string */
    uint32_t _empty_str_id;
    
    /** @brief Cached string ID for "wall-time" */
    uint32_t _wall_time_str_id;
    
    /** @brief Cached string ID for "nanoseconds" */
    uint32_t _nanoseconds_str_id;
    
    /** @brief Cached string ID for "end_timestamp_ns" */
    uint32_t _end_timestamp_ns_str_id;
    
    /** @brief Cached string ID for "tid" */
    uint32_t _tid_str_id;
    
    /** @brief Hash table for string deduplication: string -> string_id */
    std::unordered_map<std::string, uint32_t> _string_lookup;
    
    /** @brief Hash table for mapping deduplication: memory_start -> mapping_id */
    std::unordered_map<uint64_t, uint32_t> _mapping_lookup;
    
    /** @brief Hash table for location deduplication: instruction_addr -> location_id */
    std::unordered_map<uint64_t, uint32_t> _location_lookup;
    
    // Helper methods
    uint32_t intern_string(const std::string& str);
    uint32_t intern_frame(const stack_frame_t& frame);
    uint32_t intern_binary(const binary_image_t& image);
    uint32_t intern_location(const location_t& location);
};

} // namespace dd::profiler

#endif // DD_PROFILER_PROFILE_H_
