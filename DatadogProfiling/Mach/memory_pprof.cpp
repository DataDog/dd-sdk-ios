/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#include "memory_pprof.h"

#if defined(__APPLE__) && !TARGET_OS_WATCH

#include "binary_image_resolver.h"
#include "poisson_allocation_sampler.h"
#include "profile.pb-c.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <iterator>
#include <limits>
#include <memory>
#include <new>
#include <sys/mman.h>
#include <unistd.h>
#include <uuid/uuid.h>

namespace {

constexpr size_t kLocationIndexCapacity = size_t{DD_MEMORY_PPROF_MAX_UNIQUE_LOCATIONS} * 2;
constexpr size_t kMappingIndexCapacity = size_t{DD_MEMORY_PPROF_MAX_MAPPINGS} * 2;
constexpr size_t kClassNameIndexCapacity = DD_MEMORY_AGGREGATION_CAPACITY * 2;
constexpr size_t kMaxIndexProbe = 64;

enum class StringID : uint8_t {
    kEmpty,
    kAllocObjects,
    kCount,
    kAllocSpace,
    kBytes,
    kInuseObjects,
    kInuseSpace,
    kSpace,
    kAllocatedClass,
    kSource,
    kObjC,
    kSwift,
    kUnknown,
    kInitialStringCount,
};

constexpr size_t kInitialStringCount = static_cast<size_t>(StringID::kInitialStringCount);

// Each aggregate adds at most one class name; each mapping adds two strings.
static_assert(kInitialStringCount + DD_MEMORY_AGGREGATION_CAPACITY +
                  (size_t{DD_MEMORY_PPROF_MAX_MAPPINGS} * 2) <=
              std::numeric_limits<uint32_t>::max());
static_assert(DD_MEMORY_PPROF_MAX_CLASS_NAME_BYTES <= std::numeric_limits<uint32_t>::max());

constexpr int64_t string_id(StringID value) {
    return static_cast<int64_t>(value);
}

struct IndexEntry {
    uint64_t key;
    uint64_t id;
};

struct ClassNameEntry {
    const uint8_t *data;
    uint32_t id;
    uint32_t length;
};

size_t bucket_for(uint64_t key, size_t capacity) {
    key ^= key >> 30U;
    key *= 0xbf58476d1ce4e5b9ULL;
    key ^= key >> 27U;
    key *= 0x94d049bb133111ebULL;
    key ^= key >> 31U;
    return static_cast<size_t>(key) & (capacity - 1);
}

template <size_t Capacity>
IndexEntry *find_entry(std::array<IndexEntry, Capacity> &index, uint64_t key) {
    const size_t bucket = bucket_for(key, Capacity);
    for (size_t offset = 0; offset < kMaxIndexProbe; ++offset) {
        IndexEntry &entry = index[(bucket + offset) & (Capacity - 1)];
        if (entry.id == 0 || entry.key == key) {
            return &entry;
        }
    }
    return nullptr;
}

size_t mapped_bytes(size_t bytes) {
    const size_t page_size = static_cast<size_t>(getpagesize());
    return ((bytes + page_size - 1) / page_size) * page_size;
}

} // namespace

namespace dd::profiler {

/// Serializes already aggregated heap totals into one bounded pprof payload.
/// Owns its output and per-profile indexes; image metadata is borrowed.
class HeapPprofEncoder final {
public:
    static HeapPprofEncoder *create(size_t capacity);
    ~HeapPprofEncoder();
    HeapPprofEncoder(const HeapPprofEncoder &) = delete;
    HeapPprofEncoder &operator=(const HeapPprofEncoder &) = delete;
    HeapPprofEncoder(HeapPprofEncoder &&) = delete;
    HeapPprofEncoder &operator=(HeapPprofEncoder &&) = delete;
    bool encode(const dd_memory_aggregation_view_t *view,
                int64_t time_nanos, int64_t duration_nanos);
    dd_memory_pprof_view_t view() const {
        return encoded_size != 0 ? dd_memory_pprof_view_t{output, encoded_size}
                                 : dd_memory_pprof_view_t{};
    }
    dd_memory_pprof_diagnostics_t diagnostics() const {
        return counters;
    }

private:
    HeapPprofEncoder() = default;

    binary_image_cache *image_cache = nullptr;
    uint8_t *output = nullptr;
    size_t encoded_size = 0;
    size_t written = 0;
    size_t location_count = 0;
    size_t mapping_count = 0;
    int64_t next_string_id = 0;
    dd_memory_pprof_diagnostics_t counters{};
    std::array<IndexEntry, kLocationIndexCapacity> locations{};
    std::array<IndexEntry, kMappingIndexCapacity> mappings{};
    std::array<ClassNameEntry, kClassNameIndexCapacity> class_names{};

    bool append(const Perftools__Profiles__Profile &chunk);
    bool append_string(const char *value, int64_t &id, const uint8_t **encoded_data = nullptr);
    bool append_schema(int64_t time_nanos, int64_t duration_nanos);
    bool append_sample(const dd_memory_aggregate_t &aggregate);
    bool location_id(uint64_t pc, uint64_t &id);
    bool mapping_id(uint64_t pc, uint64_t &id);
    bool rounded_value(double value, int64_t &output_value);
    bool class_name_id(const dd_memory_aggregation_key_t &key, int64_t &id);
    bool intern_class_name(const char *name, size_t length, int64_t &id);
    bool invalid() {
        ++counters.invalid_profiles;
        return false;
    }
    bool limit() {
        ++counters.limit_failures;
        return false;
    }
};

namespace {

// Partial construction and the opaque C handle use the same allocation owner.
struct EncoderDeleter {
    void operator()(HeapPprofEncoder *encoder) const noexcept {
        if (encoder != nullptr) {
            encoder->~HeapPprofEncoder();
            std::free(encoder);
        }
    }
};

using EncoderOwner = std::unique_ptr<HeapPprofEncoder, EncoderDeleter>;

} // namespace

HeapPprofEncoder *HeapPprofEncoder::create(size_t capacity) {
    if (capacity == 0 || capacity > DD_MEMORY_PPROF_MAX_PAYLOAD_BYTES) {
        return nullptr;
    }
    // calloc and explicit member initialization agree on the initial state;
    // optimized builds can elide redundant clearing of the large indexes.
    void *storage = std::calloc(1, sizeof(HeapPprofEncoder));
    if (storage == nullptr) {
        return nullptr;
    }
    EncoderOwner encoder(new (storage) HeapPprofEncoder);
    encoder->counters.max_payload_bytes = capacity;
    void *output_storage = mmap(nullptr, capacity,
                                PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (output_storage == MAP_FAILED) {
        return nullptr;
    }
    encoder->output = static_cast<uint8_t *>(output_storage);

    encoder->image_cache = shared_binary_image_cache();
    if (encoder->image_cache == nullptr) {
        return nullptr;
    }

    encoder->counters.storage_bytes =
        sizeof(HeapPprofEncoder) + mapped_bytes(capacity);
    return encoder.release();
}

HeapPprofEncoder::~HeapPprofEncoder() {
    if (output != nullptr) {
        munmap(output, static_cast<size_t>(counters.max_payload_bytes));
    }
}

bool HeapPprofEncoder::append(const Perftools__Profiles__Profile &chunk) {
    const size_t size = perftools__profiles__profile__get_packed_size(&chunk);
    const size_t capacity = static_cast<size_t>(counters.max_payload_bytes);
    if (written > capacity || size > capacity - written) {
        return limit();
    }
    const size_t packed = perftools__profiles__profile__pack(&chunk, output + written);
    if (packed != size) {
        return invalid();
    }
    written += packed;
    return true;
}

bool HeapPprofEncoder::append_string(const char *value, int64_t &id,
                                    const uint8_t **encoded_data) {
    Perftools__Profiles__Profile chunk = PERFTOOLS__PROFILES__PROFILE__INIT;
    char *string = const_cast<char *>(value);
    chunk.n_string_table = 1;
    chunk.string_table = &string;
    if (!append(chunk)) {
        return false;
    }
    id = next_string_id++;
    if (encoded_data != nullptr) {
        // This chunk contains one string field, ending in its raw bytes.
        // Borrow the stable output buffer instead of retaining another copy.
        *encoded_data = output + written - std::strlen(value);
    }
    return true;
}

bool HeapPprofEncoder::append_schema(int64_t time_nanos,
                                     int64_t duration_nanos) {
    Perftools__Profiles__Profile chunk = PERFTOOLS__PROFILES__PROFILE__INIT;
    const std::array<const char *, kInitialStringCount> strings = {
        "", "alloc_objects", "count", "alloc_space", "bytes",
        "inuse_objects", "inuse_space", "space", "allocation class", "source",
        "objc", "swift", "unknown",
    };
    std::array<char *, kInitialStringCount> string_pointers{};
    for (size_t index = 0; index < kInitialStringCount; ++index) {
        string_pointers[index] = const_cast<char *>(strings[index]);
    }
    std::array<Perftools__Profiles__ValueType, 4> types = {
        {
            PERFTOOLS__PROFILES__VALUE_TYPE__INIT, PERFTOOLS__PROFILES__VALUE_TYPE__INIT,
            PERFTOOLS__PROFILES__VALUE_TYPE__INIT, PERFTOOLS__PROFILES__VALUE_TYPE__INIT,
        },
    };
    const std::array<int64_t, 4> type_ids = {
        string_id(StringID::kAllocObjects),
        string_id(StringID::kAllocSpace),
        string_id(StringID::kInuseObjects),
        string_id(StringID::kInuseSpace),
    };
    std::array<Perftools__Profiles__ValueType *, 4> type_pointers{};
    for (size_t index = 0; index < 4; ++index) {
        types[index].type = type_ids[index];
        types[index].unit = index % 2 == 0 ? string_id(StringID::kCount) : string_id(StringID::kBytes);
        type_pointers[index] = &types[index];
    }
    Perftools__Profiles__ValueType period = PERFTOOLS__PROFILES__VALUE_TYPE__INIT;
    period.type = string_id(StringID::kSpace);
    period.unit = string_id(StringID::kBytes);
    chunk.n_string_table = kInitialStringCount;
    chunk.string_table = string_pointers.data();
    chunk.n_sample_type = 4;
    chunk.sample_type = type_pointers.data();
    chunk.period_type = &period;
    chunk.period = poisson_allocation_sampler::sampling_interval();
    chunk.default_sample_type = string_id(StringID::kInuseSpace);
    chunk.time_nanos = time_nanos;
    chunk.duration_nanos = duration_nanos;
    next_string_id = kInitialStringCount;
    return append(chunk);
}

bool HeapPprofEncoder::rounded_value(double value, int64_t &output_value) {
    if (std::isnan(value) || value < 0.0) {
        return invalid();
    }
    // double(INT64_MAX) rounds up to 2^63. Check that boundary before casting
    // or rounding so positive infinity and large estimates cannot overflow.
    if (value >= 0x1p63) {
        output_value = std::numeric_limits<int64_t>::max();
        ++counters.saturated_values;
    } else {
        output_value = static_cast<int64_t>(std::round(value));
    }
    return true;
}

bool HeapPprofEncoder::class_name_id(
    const dd_memory_aggregation_key_t &key, int64_t &id) {
    id = 0;
    char name[DD_MEMORY_PPROF_MAX_CLASS_NAME_BYTES + 1];
    size_t length = 0;
    if (key.swift_metadata != nullptr) {
        const dd_swift_class_name_t resolved =
            key.swift_name_resolver(key.swift_metadata);
        if (resolved.length == 0) {
            return true;
        }
        if (resolved.data == nullptr ||
            resolved.length > DD_MEMORY_PPROF_MAX_CLASS_NAME_BYTES) {
            ++counters.omitted_class_names;
            return true;
        }
        length = static_cast<size_t>(resolved.length);
        if (std::memchr(resolved.data, '\0', length) != nullptr) {
            ++counters.omitted_class_names;
            return true;
        }
        std::memcpy(name, resolved.data, length);
        name[length] = '\0';
    } else if (key.class_name != nullptr) {
        length = strnlen(
            key.class_name, DD_MEMORY_PPROF_MAX_CLASS_NAME_BYTES + 1);
        if (length == 0) {
            return true;
        }
        if (length > DD_MEMORY_PPROF_MAX_CLASS_NAME_BYTES) {
            ++counters.omitted_class_names;
            return true;
        }
        std::memcpy(name, key.class_name, length + 1);
    } else {
        return true;
    }
    return intern_class_name(name, length, id);
}

bool HeapPprofEncoder::intern_class_name(const char *name, size_t length, int64_t &id) {
    uint64_t hash = 0xcbf29ce484222325ULL;
    for (size_t index = 0; index < length; ++index) {
        hash = (hash ^ static_cast<unsigned char>(name[index])) * 0x100000001b3ULL;
    }
    const size_t bucket = bucket_for(hash, kClassNameIndexCapacity);
    for (size_t offset = 0; offset < kMaxIndexProbe; ++offset) {
        ClassNameEntry &entry = class_names[(bucket + offset) & (kClassNameIndexCapacity - 1)];
        if (entry.id != 0) {
            if (entry.length == length && std::memcmp(entry.data, name, length) == 0) {
                id = entry.id;
                return true;
            }
            continue;
        }
        const uint8_t *encoded_data = nullptr;
        if (!append_string(name, id, &encoded_data)) {
            return false;
        }
        entry = {encoded_data, static_cast<uint32_t>(id), static_cast<uint32_t>(length)};
        return true;
    }
    // Deduplication must not reject a profile merely because its index clusters.
    return append_string(name, id);
}

bool HeapPprofEncoder::mapping_id(uint64_t pc, uint64_t &id) {
    id = 0;
    binary_image_t image{};
    if (!image_cache->lookup(pc, &image)) {
        ++counters.unresolved_locations;
        return true;
    }

    IndexEntry *entry = find_entry(mappings, image.load_address);
    if (entry == nullptr) {
        return limit();
    }
    if (entry->id != 0) {
        id = entry->id;
        return true;
    }
    if (mapping_count >= DD_MEMORY_PPROF_MAX_MAPPINGS) {
        return limit();
    }

    uuid_string_t uuid;
    uuid_unparse_upper(image.uuid, uuid);
    int64_t build_id = 0;
    int64_t filename_id = 0;
    if (!append_string(uuid, build_id) ||
        (image.filename != nullptr && !append_string(image.filename, filename_id))) {
        return false;
    }
    Perftools__Profiles__Mapping mapping = PERFTOOLS__PROFILES__MAPPING__INIT;
    mapping.id = mapping_count + 1;
    mapping.memory_start = image.load_address;
    mapping.build_id = build_id;
    mapping.filename = filename_id;
    Perftools__Profiles__Mapping *mapping_pointer = &mapping;
    Perftools__Profiles__Profile chunk = PERFTOOLS__PROFILES__PROFILE__INIT;
    chunk.n_mapping = 1;
    chunk.mapping = &mapping_pointer;
    if (!append(chunk)) {
        return false;
    }
    ++mapping_count;
    entry->key = image.load_address;
    entry->id = mapping.id;
    id = mapping.id;
    return true;
}

bool HeapPprofEncoder::location_id(uint64_t pc, uint64_t &id) {
    IndexEntry *entry = find_entry(locations, pc);
    if (entry == nullptr) {
        return limit();
    }
    if (entry->id != 0) {
        id = entry->id;
        return true;
    }
    if (location_count >= DD_MEMORY_PPROF_MAX_UNIQUE_LOCATIONS) {
        return limit();
    }

    Perftools__Profiles__Location location = PERFTOOLS__PROFILES__LOCATION__INIT;
    location.id = location_count + 1;
    location.address = pc;
    if (!mapping_id(pc, location.mapping_id)) {
        return false;
    }
    Perftools__Profiles__Location *location_pointer = &location;
    Perftools__Profiles__Profile chunk = PERFTOOLS__PROFILES__PROFILE__INIT;
    chunk.n_location = 1;
    chunk.location = &location_pointer;
    if (!append(chunk)) {
        return false;
    }
    ++location_count;
    entry->key = pc;
    entry->id = location.id;
    id = location.id;
    return true;
}

bool HeapPprofEncoder::append_sample(const dd_memory_aggregate_t &aggregate) {
    const dd_memory_aggregation_key_t &key = aggregate.key;
    const size_t frame_count = key.frame_count;
    if (frame_count > DD_MEMORY_LIVE_SET_MAX_FRAMES ||
        (key.swift_metadata == nullptr) != (key.swift_name_resolver == nullptr) ||
        (key.class_name != nullptr && key.swift_metadata != nullptr)) {
        return invalid();
    }
    int64_t values[4];
    if (!rounded_value(aggregate.alloc_objects, values[0]) ||
        !rounded_value(aggregate.alloc_space, values[1]) ||
        !rounded_value(aggregate.inuse_objects, values[2]) ||
        !rounded_value(aggregate.inuse_space, values[3])) {
        return false;
    }
    uint64_t location_ids[DD_MEMORY_LIVE_SET_MAX_FRAMES];
    const auto *frame = std::begin(key.frames);
    for (size_t index = 0; index < frame_count; ++index, ++frame) {
        if (!location_id(*frame, location_ids[index])) {
            return false;
        }
    }
    int64_t class_id = 0;
    if (!class_name_id(key, class_id)) {
        return false;
    }
    Perftools__Profiles__Label source_label = PERFTOOLS__PROFILES__LABEL__INIT;
    source_label.key = string_id(StringID::kSource);
    switch (key.source) {
        case DD_MEMORY_LIVE_SAMPLE_SOURCE_OBJC: source_label.str = string_id(StringID::kObjC); break;
        case DD_MEMORY_LIVE_SAMPLE_SOURCE_SWIFT: source_label.str = string_id(StringID::kSwift); break;
        default: source_label.str = string_id(StringID::kUnknown); break;
    }
    Perftools__Profiles__Label class_label = PERFTOOLS__PROFILES__LABEL__INIT;
    class_label.key = string_id(StringID::kAllocatedClass);
    class_label.str = class_id;
    Perftools__Profiles__Label *labels[2] = {&source_label, &class_label};

    Perftools__Profiles__Sample output_sample = PERFTOOLS__PROFILES__SAMPLE__INIT;
    output_sample.n_location_id = frame_count;
    output_sample.location_id = location_ids;
    output_sample.n_value = 4;
    output_sample.value = values;
    output_sample.n_label = class_id == 0 ? 1 : 2;
    output_sample.label = labels;
    Perftools__Profiles__Sample *sample_pointer = &output_sample;
    Perftools__Profiles__Profile chunk = PERFTOOLS__PROFILES__PROFILE__INIT;
    chunk.n_sample = 1;
    chunk.sample = &sample_pointer;
    return append(chunk);
}

bool HeapPprofEncoder::encode(const dd_memory_aggregation_view_t *view,
                              int64_t time_nanos, int64_t duration_nanos) {
    encoded_size = 0;
    if (view == nullptr || time_nanos < 0 || duration_nanos < 0 ||
        (view->count != 0 && view->samples == nullptr)) {
        return invalid();
    }
    if (view->count > DD_MEMORY_AGGREGATION_CAPACITY) {
        return limit();
    }
    if (view->count == 0) {
        ++counters.empty_profiles_skipped;
        return false;
    }

    written = 0;
    location_count = 0;
    mapping_count = 0;
    locations.fill({});
    mappings.fill({});
    class_names.fill({});
    // Each chunk is a subset of one Profile. Repeated fields concatenate on
    // the wire; references may precede or follow their definitions. This keeps
    // protobuf message objects on the stack instead of retaining a full tree.
    if (!append_schema(time_nanos, duration_nanos)) {
        return false;
    }
    for (size_t index = 0; index < view->count; ++index) {
        if (!append_sample(view->samples[index])) {
            return false;
        }
    }
    encoded_size = written;
    ++counters.encoded_profiles;
    counters.encoded_size_high_water = std::max(counters.encoded_size_high_water,
                                                static_cast<uint64_t>(encoded_size));
    return true;
}

} // namespace dd::profiler

extern "C" dd_memory_pprof_encoder_t *dd_memory_pprof_encoder_create(
    size_t max_payload_bytes) {
    return dd::profiler::HeapPprofEncoder::create(max_payload_bytes);
}

extern "C" void dd_memory_pprof_encoder_destroy(dd_memory_pprof_encoder_t *encoder) {
    dd::profiler::EncoderOwner owner(encoder);
}

extern "C" bool dd_memory_pprof_encoder_encode(
    dd_memory_pprof_encoder_t *encoder, const dd_memory_aggregation_view_t *view,
    int64_t time_nanos, int64_t duration_nanos) {
    return encoder != nullptr && encoder->encode(view, time_nanos, duration_nanos);
}

extern "C" dd_memory_pprof_view_t dd_memory_pprof_encoder_view(
    const dd_memory_pprof_encoder_t *encoder) {
    return encoder != nullptr ? encoder->view() : dd_memory_pprof_view_t{};
}

extern "C" dd_memory_pprof_diagnostics_t dd_memory_pprof_encoder_diagnostics(
    const dd_memory_pprof_encoder_t *encoder) {
    return encoder != nullptr ? encoder->diagnostics() : dd_memory_pprof_diagnostics_t{};
}

#endif // defined(__APPLE__) && !TARGET_OS_WATCH
