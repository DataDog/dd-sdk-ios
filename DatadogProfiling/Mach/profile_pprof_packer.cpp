/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

/**
 * @file profile_packer.cpp
 * @brief Converts internal profile data structures to protobuf format for serialization
 * 
 * This module implements the conversion from Datadog's internal profiling data structures
 * to the standardized pprof protobuf format. The pprof format is a Google-defined format
 * for representing profiling data that can be consumed by various profiling tools.
 * 
 * Key responsibilities:
 * - Convert internal string tables, functions, mappings, locations, and samples to protobuf
 * - Handle memory allocation consistently through a custom allocator
 * - Serialize the final protobuf structure to binary format
 * 
 * The implementation follows the pprof specification and ensures all data is properly
 * deduplicated and referenced by ID rather than duplicated content.
 */

#include "profile_pprof_packer.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#include "profile.h"
#include "profile.pb-c.h"

/**
 * @brief Custom allocator functions for protobuf-c memory management
 * 
 * These functions provide a consistent allocation interface that wraps
 * standard malloc/free. Using a custom allocator ensures all protobuf
 * memory can be tracked and cleaned up properly.
 */

/** @brief Allocation function wrapper around malloc */
static void* sys_malloc(void* allocator_data, size_t size) {
    (void)allocator_data;
    return malloc(size);
}

/** @brief Deallocation function wrapper around free */
static void sys_free(void* allocator_data, void* ptr) {
    (void)allocator_data;
    free(ptr);
}

/** @brief Global allocator instance used for all protobuf allocations */
static ProtobufCAllocator profile_allocator = {
    sys_malloc,
    sys_free,
    nullptr  // allocator_data
};

/** @brief Allocate memory using the protobuf allocator */
static inline void* pb_alloc(ProtobufCAllocator* allocator, size_t size) {
    return allocator->alloc(allocator->allocator_data, size);
}

namespace dd::profiler {

/**
 * @brief Helper function forward declarations
 * 
 * These functions handle the conversion of specific data types from the internal
 * profile representation to protobuf structures. Each function is responsible
 * for allocating and populating the corresponding protobuf message type.
 */

/** @brief Convert string table to protobuf format with proper memory allocation */
void perftools__profiles__profile__add_strings(const std::vector<std::string>& strings, Perftools__Profiles__Profile* pprof, ProtobufCAllocator* allocator);

/** @brief Set sample type definitions (e.g., "cpu"/"nanoseconds", "wall"/"nanoseconds") */
void perftools__profiles__profile__set_sample_type(int64_t type, int64_t unit, Perftools__Profiles__Profile* pprof, ProtobufCAllocator* allocator);

/** @brief Set period type and value for sampling interval */
void perftools__profiles__profile__set_period(int64_t type, int64_t unit, int64_t period, Perftools__Profiles__Profile* pprof, ProtobufCAllocator* allocator);

/** @brief Convert memory mapping information to protobuf format */
void perftools__profiles__profile__add_mappings(const std::vector<mapping_t>& mappings, Perftools__Profiles__Profile* pprof, ProtobufCAllocator* allocator);

/** @brief Convert code location information to protobuf format */
void perftools__profiles__profile__add_locations(const std::vector<location_t>& locations, Perftools__Profiles__Profile* pprof, ProtobufCAllocator* allocator);

/** @brief Convert sample data to protobuf format */
void perftools__profiles__profile__add_samples(const std::vector<sample_t>& samples, Perftools__Profiles__Profile* pprof, ProtobufCAllocator* allocator);

/**
 * @brief Pack profile data into pprof protobuf binary format
 * 
 * This is the main entry point for converting profile data to the
 * standardized pprof binary format. The function:
 * 
 * 1. Creates a protobuf Profile message structure
 * 2. Converts all internal data (strings, functions, mappings, etc.) to protobuf format
 * 3. Serializes the protobuf message to binary data
 * 4. Returns ownership of the allocated buffer to the caller
 * 
 * @param prof The profile data to pack
 * @param data Output parameter - pointer to allocated buffer containing serialized data
 * @return Size of the serialized data in bytes, or 0 on failure
 * 
 * @note The caller is responsible for freeing the returned buffer with free()
 * @note All protobuf memory is allocated using the custom allocator and cleaned up automatically
 */
size_t profile_pprof_pack(const profile& prof, uint8_t** data) {
    if (!data) return 0;
    
    // Allocate and initialize the main protobuf profile structure
    auto* pprof = static_cast<Perftools__Profiles__Profile*>(
        pb_alloc(&profile_allocator, sizeof(Perftools__Profiles__Profile))
    );
    perftools__profiles__profile__init(pprof);
    
    // Convert each component of the profile to protobuf format
    perftools__profiles__profile__add_strings(prof.strings(), pprof, &profile_allocator);
    perftools__profiles__profile__set_sample_type(prof.wall_time_str_id(), prof.nanoseconds_str_id(), pprof, &profile_allocator);
    perftools__profiles__profile__set_period(prof.wall_time_str_id(), prof.nanoseconds_str_id(), prof.sampling_interval_ns(), pprof, &profile_allocator);
    perftools__profiles__profile__add_mappings(prof.mappings(), pprof, &profile_allocator);
    perftools__profiles__profile__add_locations(prof.locations(), pprof, &profile_allocator);
    perftools__profiles__profile__add_samples(prof.samples(), pprof, &profile_allocator);
    
    // Calculate required buffer size and serialize to binary format
    size_t packed_size = perftools__profiles__profile__get_packed_size(pprof);
    
    if (packed_size == 0) {
        perftools__profiles__profile__free_unpacked(pprof, &profile_allocator);
        return 0;
    }
    
    uint8_t* buffer = static_cast<uint8_t*>(malloc(packed_size));
    if (!buffer) {
        perftools__profiles__profile__free_unpacked(pprof, &profile_allocator);
        return 0;
    }
    
    size_t actual_size = pprof_pb_message_pack(
        reinterpret_cast<const ProtobufCMessage*>(pprof),
        buffer
    );
    
    // Clean up protobuf structures (buffer is transferred to caller)
    perftools__profiles__profile__free_unpacked(pprof, &profile_allocator);
    
    if (actual_size == 0) {
        free(buffer);
        return 0;
    }
    
    *data = buffer;
    return actual_size;
}

/**
 * @brief Convert string table to protobuf format
 * 
 * Copies all strings from the internal string table to protobuf format.
 * Each string is allocated using the protobuf allocator to ensure
 * consistent memory management.
 */
void perftools__profiles__profile__add_strings(const std::vector<std::string>& strings, Perftools__Profiles__Profile* pprof, ProtobufCAllocator* allocator) {
    pprof->n_string_table = strings.size();
    if (strings.empty()) return;
    
    pprof->string_table = static_cast<char**>(pb_alloc(allocator, strings.size() * sizeof(char*)));
    
    for (size_t i = 0; i < strings.size(); ++i) {
        size_t str_len = strings[i].length() + 1;  // +1 for null terminator
        pprof->string_table[i] = static_cast<char*>(pb_alloc(allocator, str_len));
        memcpy(pprof->string_table[i], strings[i].c_str(), str_len);
    }
}

void perftools__profiles__profile__set_sample_type(int64_t type, int64_t unit, Perftools__Profiles__Profile* pprof, ProtobufCAllocator* allocator) {
    // Create wall-time sample types
    pprof->n_sample_type = 1;
    pprof->sample_type = static_cast<Perftools__Profiles__ValueType**>(
        pb_alloc(allocator, pprof->n_sample_type * sizeof(Perftools__Profiles__ValueType*))
    );
    
    auto* sample_type_0 = static_cast<Perftools__Profiles__ValueType*>(
        pb_alloc(allocator, sizeof(Perftools__Profiles__ValueType))
    );
    perftools__profiles__value_type__init(sample_type_0);
    sample_type_0->type = type;
    sample_type_0->unit = unit;
    pprof->sample_type[0] = sample_type_0;
}

void perftools__profiles__profile__set_period(int64_t type, int64_t unit, int64_t period, Perftools__Profiles__Profile* pprof, ProtobufCAllocator* allocator) {
    // Create a separate ValueType for period_type
    auto* period_type = static_cast<Perftools__Profiles__ValueType*>(
        pb_alloc(allocator, sizeof(Perftools__Profiles__ValueType))
    );
    perftools__profiles__value_type__init(period_type);
    period_type->type = type;
    period_type->unit = unit;
    pprof->period_type = period_type;
    
    // Set the period value
    pprof->period = period;
}

void perftools__profiles__profile__add_mappings(const std::vector<mapping_t>& mappings, Perftools__Profiles__Profile* pprof, ProtobufCAllocator* allocator) {
    pprof->n_mapping = mappings.size();
    if (mappings.empty()) return;
    
    pprof->mapping = static_cast<Perftools__Profiles__Mapping**>(
        pb_alloc(allocator, mappings.size() * sizeof(Perftools__Profiles__Mapping*))
    );
    
    for (size_t i = 0; i < mappings.size(); ++i) {
        auto* mapping = static_cast<Perftools__Profiles__Mapping*>(
            pb_alloc(allocator, sizeof(Perftools__Profiles__Mapping))
        );
        perftools__profiles__mapping__init(mapping);
        mapping->id = static_cast<uint64_t>(i + 1);
        mapping->memory_start = mappings[i].memory_start;
        mapping->filename = mappings[i].filename_id;
        mapping->build_id = mappings[i].build_id;
        pprof->mapping[i] = mapping;
    }
}

void perftools__profiles__profile__add_locations(const std::vector<location_t>& locations, Perftools__Profiles__Profile* pprof, ProtobufCAllocator* allocator) {
    pprof->n_location = locations.size();
    if (locations.empty()) return;
    
    pprof->location = static_cast<Perftools__Profiles__Location**>(
        pb_alloc(allocator, locations.size() * sizeof(Perftools__Profiles__Location*))
    );
    
    for (size_t i = 0; i < locations.size(); ++i) {
        auto* location = static_cast<Perftools__Profiles__Location*>(
            pb_alloc(allocator, sizeof(Perftools__Profiles__Location))
        );
        perftools__profiles__location__init(location);
        location->id = static_cast<uint64_t>(i + 1);
        location->mapping_id = locations[i].mapping_id;
        location->address = locations[i].address;
        
        // No line information - leave n_line = 0 and line = NULL
        
        pprof->location[i] = location;
    }
}

void perftools__profiles__profile__add_samples(const std::vector<sample_t>& samples, Perftools__Profiles__Profile* pprof, ProtobufCAllocator* allocator) {
    pprof->n_sample = samples.size();
    if (pprof->n_sample == 0) return;
    
    pprof->sample = static_cast<Perftools__Profiles__Sample**>(
        pb_alloc(allocator, pprof->n_sample * sizeof(Perftools__Profiles__Sample*))
    );
    
    for (size_t sample_idx = 0; sample_idx < samples.size(); ++sample_idx) {
        const auto& src_sample = samples[sample_idx];
        auto* sample = static_cast<Perftools__Profiles__Sample*>(
            pb_alloc(allocator, sizeof(Perftools__Profiles__Sample))
        );
        perftools__profiles__sample__init(sample);
        
        // Set location IDs
        sample->n_location_id = src_sample.location_ids.size();
        sample->location_id = static_cast<uint64_t*>(
            pb_alloc(allocator, src_sample.location_ids.size() * sizeof(uint64_t))
        );
        for (size_t i = 0; i < src_sample.location_ids.size(); ++i) {
            sample->location_id[i] = src_sample.location_ids[i];
        }
        
        // Set values
        sample->n_value = src_sample.values.size();
        sample->value = static_cast<int64_t*>(
            pb_alloc(allocator, src_sample.values.size() * sizeof(int64_t))
        );
        for (size_t i = 0; i < src_sample.values.size(); ++i) {
            sample->value[i] = src_sample.values[i];
        }
        
        // Set labels
        sample->n_label = src_sample.labels.size();
        if (sample->n_label > 0) {
            sample->label = static_cast<Perftools__Profiles__Label**>(
                pb_alloc(allocator, sample->n_label * sizeof(Perftools__Profiles__Label*))
            );
            for (size_t i = 0; i < src_sample.labels.size(); ++i) {
                auto* label = static_cast<Perftools__Profiles__Label*>(
                    pb_alloc(allocator, sizeof(Perftools__Profiles__Label))
                );
                perftools__profiles__label__init(label);
                label->key = src_sample.labels[i].key_id;
                label->str = src_sample.labels[i].str_id;
                label->num = src_sample.labels[i].num;
                label->num_unit = src_sample.labels[i].num_unit_id;
                sample->label[i] = label;
            }
        }
        
        pprof->sample[sample_idx] = sample;
    }
}

} // namespace dd::profiler

#endif // __APPLE__ && !TARGET_OS_WATCH
