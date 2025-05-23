/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
internal import SwiftProtobuf

// swiftlint:disable duplicate_imports
#if SPM_BUILD
internal import DatadogMachProfiler
#endif
// swiftlint:enable duplicate_imports

private extension String {
    static let empty = ""
    static let hexFormat = "0x%llx"
}

internal class Profile {
    private var profile: Perftools_Profiles_Profile
    private var stringTable: [String: Int] = [:]
    private var locationTable: [UInt64: UInt64] = [:]
    private var sampleTable: [[UInt64]: Int] = [:]
    private var mappingTable: [UInt64: UInt64] = [:] 
    
    init(samplingIntervalMs: UInt32) {
        profile = Perftools_Profiles_Profile()
        
        // Initialize string table with empty string
        profile.stringTable.append(.empty)
        stringTable[.empty] = 0
        
        // Initialize sample types
        var sampleType = Perftools_Profiles_ValueType()
        sampleType.type = addString("cpu")
        sampleType.unit = addString("nanoseconds")
        profile.sampleType.append(sampleType)
        
        // Set sampling period
        profile.period = Int64(samplingIntervalMs * 1_000_000) // to nanoseconds
        profile.periodType = sampleType

        let capacity = 1000
        sampleTable.reserveCapacity(capacity)
        profile.sample.reserveCapacity(capacity)
        profile.location.reserveCapacity(capacity)
        profile.function.reserveCapacity(capacity)
    }
    
    private func addString(_ str: String) -> Int64 {
        if let index = stringTable[str] {
            return Int64(index)
        }
        let index = profile.stringTable.count
        profile.stringTable.append(str)
        stringTable[str] = index
        return Int64(index)
    }

    private func addMapping(_ frame: stack_frame_t) -> UInt64 {
        // Check if we already have a mapping for this binary
        if let mappingId = mappingTable[frame.image.load_address] {
            return mappingId
        }
        
        var mapping = Perftools_Profiles_Mapping()
        mapping.id = UInt64(profile.mapping.count + 1)
        mapping.memoryStart = frame.image.load_address
        mapping.memoryLimit = .max
        mapping.fileOffset = 0 // For unsymbolized profiles, we don't need file offset
        mapping.filename = addString(.empty)
        mapping.buildID = addString(UUID(uuid: frame.image.uuid).uuidString)
        mapping.hasFunctions_p = false // No functions in unsymbolized profile
        mapping.hasFilenames_p = false
        mapping.hasLineNumbers_p = false
        mapping.hasInlineFrames_p = false
        
        profile.mapping.append(mapping)
        mappingTable[frame.image.load_address] = mapping.id
        return mapping.id
    }
    
    private func addLocation(_ frame: stack_frame_t) -> UInt64 {
        if let id = locationTable[frame.instruction_ptr] {
            return id
        }
        
        var location = Perftools_Profiles_Location()
        location.id = UInt64(profile.location.count + 1)
        
        location.address = frame.instruction_ptr // Use full address
        location.mappingID = addMapping(frame)
        
        // For unsymbolized profiles, create a function entry with the address
        var function = Perftools_Profiles_Function()
        function.id = UInt64(profile.function.count + 1)
        function.name = addString(String(format: .hexFormat, frame.instruction_ptr))
        function.systemName = addString(.empty)
        function.filename = addString(.empty)
        function.startLine = 0
        profile.function.append(function)
        
        // Create line entry
        var line = Perftools_Profiles_Line()
        line.functionID = function.id
        line.line = 0
        location.line.append(line)
        
        profile.location.append(location)
        locationTable[frame.instruction_ptr] = location.id
        return location.id
    }

    func addSamples(_ traces: UnsafeBufferPointer<stack_trace_t>) {
        for trace in traces {
            var locationIds: [UInt64] = []
            locationIds.reserveCapacity(Int(trace.frame_count))
            
            for i in 0..<Int(trace.frame_count) {
                let frame = trace.frames[i]
                let locationId = addLocation(frame)
                locationIds.append(locationId)
            }
            
            // Add sample
            if let existingIndex = sampleTable[locationIds] {
                profile.sample[existingIndex].value[0] += 1
            } else {
                var sample = Perftools_Profiles_Sample()
                sample.locationID = locationIds
                sample.value = [1]
                profile.sample.append(sample)
                sampleTable[locationIds] = profile.sample.count - 1
            }
        }
    }

    func serializedData(partial: Bool = false) throws -> Data {
        try profile.serializedData(partial: partial)
    }
}

internal class MachProfiler {
    private let profiler: OpaquePointer
    private let profile: Profile
    
    init(
        samplingIntervalMs: UInt32 = 1,
        maxStackDepth: UInt32 = 64,
        currentThreadOnly: Bool = false,
        maxBufferSize: Int = 100
    ) {
        var config = sampling_config_t(
            sampling_interval_ms: samplingIntervalMs,
            max_stack_depth: maxStackDepth,
            profile_current_thread_only: currentThreadOnly ? 1: 0,
            max_buffer_size: maxBufferSize
        )
        
        profile = Profile(samplingIntervalMs: samplingIntervalMs)
        profiler = profiler_create(&config, stackTraceCallback, Unmanaged.passUnretained(profile).toOpaque())!
    }
    
    deinit {
        profiler_destroy(profiler)
    }
    
    @discardableResult
    func start() -> Bool {
        profiler_start(profiler) != 0
    }
    
    func stop() {
        profiler_stop(profiler)
    }
    
    var isRunning: Bool {
        profiler_is_running(profiler) != 0
    }

    func serializedData(partial: Bool = false) throws -> Data {
        try profile.serializedData(partial: partial)
    }
}

private func stackTraceCallback(traces: UnsafePointer<stack_trace_t>?, count: Int, userData: UnsafeMutableRawPointer?) {
    guard
        let traces = traces,
        let userData = userData
    else { return }
    
    let profile = Unmanaged<Profile>.fromOpaque(userData).takeUnretainedValue()
    let buffer = UnsafeBufferPointer(start: traces, count: count)
    profile.addSamples(buffer)
}
