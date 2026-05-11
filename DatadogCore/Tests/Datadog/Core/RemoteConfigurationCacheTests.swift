/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogCore

class RemoteConfigurationCacheTests: XCTestCase {
    private var coreDir = temporaryUniqueCoreDirectory()

    override func setUp() {
        super.setUp()
        coreDir = temporaryUniqueCoreDirectory()
        coreDir.create()
    }

    override func tearDown() {
        coreDir.delete()
        super.tearDown()
    }

    // MARK: Read at init

    func testReturnsNilWhenNoCacheExists() {
        let cache = RemoteConfigurationCache(directory: coreDir.coreDirectory)
        XCTAssertNil(cache.data)
    }

    // MARK: Persistence across instances (simulates app relaunch)

    func testDataReadBackOnNextInit() {
        let payload = Data("{\"session_sample_rate\":50}".utf8)

        // First "launch": save data
        let cache1 = RemoteConfigurationCache(directory: coreDir.coreDirectory)
        cache1.save(payload)

        // Second "launch": a fresh instance must read it back
        let cache2 = RemoteConfigurationCache(directory: coreDir.coreDirectory)
        XCTAssertEqual(cache2.data, payload)
    }

    func testSaveOverwritesPreviousFile() {
        let first  = Data("{\"v\":1}".utf8)
        let second = Data("{\"v\":2}".utf8)

        RemoteConfigurationCache(directory: coreDir.coreDirectory).save(first)
        RemoteConfigurationCache(directory: coreDir.coreDirectory).save(second)

        let cache = RemoteConfigurationCache(directory: coreDir.coreDirectory)
        XCTAssertEqual(cache.data, second)
    }

    // MARK: Failure resilience

    func testSaveFailsSilentlyWhenDirectoryMissing() {
        let missing = Directory(url: URL(fileURLWithPath: "/no/such/path/"))
        let cache   = RemoteConfigurationCache(directory: missing)
        // Must not crash
        cache.save(Data("{\"k\":\"v\"}".utf8))
    }
}
