/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import XCTest

extension XCTestCase {
    /// Calls given closures concurrently from multiple threads.
    /// Each closure is called only once.
    func callConcurrently(
        _ closure1: @escaping () -> Void,
        _ closure2: @escaping () -> Void,
        _ closure3: (() -> Void)? = nil,
        _ closure4: (() -> Void)? = nil,
        _ closure5: (() -> Void)? = nil,
        _ closure6: (() -> Void)? = nil
    ) {
        callConcurrently(
            closures: [closure1, closure2, closure3, closure4, closure5, closure6].compactMap { $0 },
            iterations: 1
        )
    }

    /// Calls given closures concurrently from multiple threads.
    /// Each closure will be called the number of times given by `iterations` count.
    func callConcurrently(closures: [() -> Void], iterations: Int = 1) {
        var moreClosures: [() -> Void] = []
        (0..<iterations).forEach { _ in moreClosures.append(contentsOf: closures) }
        let randomizedClosures = moreClosures.shuffled()

        DispatchQueue.concurrentPerform(iterations: randomizedClosures.count) { iteration in
            randomizedClosures[iteration]()
        }
    }

    /// Waits until given `condition` returns `true` and then fulfills the `expectation`.
    /// It executes `condition()` block on the main thread, in every run loop.
    func wait(until condition: @escaping () -> Bool, andThenFulfill expectation: XCTestExpectation) {
        if condition() {
            expectation.fulfill()
        } else {
            OperationQueue.main.addOperation { [weak self] in
                self?.wait(until: condition, andThenFulfill: expectation)
            }
        }
    }

    /// Asserts that two dictionaries are equal.
    /// It uses debug string representation of values to check equality of `Any` values.
    func AssertDictionariesEqual(
        _ dictionary1: [String: Any],
        _ dictionary2: [String: Any],
        _ message: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        AssertDictionariesEqual(
            dictionary1,
            dictionary2,
            keyPath: "",
            message: message ?? "",
            file: file,
            line: line
        )
    }

    private func AssertDictionariesEqual(
        _ dictionary1: [String: Any],
        _ dictionary2: [String: Any],
        keyPath: String,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if dictionary1.keys.count != dictionary2.keys.count {
            XCTFail(
                """
                🔥 Failure: \(message)

                Both dictionaries have different number of keys:
                    * (1) \(dictionary1.keys.count) keys
                    * (2) \(dictionary2.keys.count) keys
                """,
                file: file,
                line: line
            )
            return
        }

        for (key, value1) in dictionary1 {
            let currentKeyPath = keyPath.isEmpty ? "\(key)" : "\(keyPath).\(key)"

            guard let value2 = dictionary2[key] else {
                XCTFail(
                    """
                    🔥 Failure: \(message)

                    Second dictionary doesn't define value for key path: '\(currentKeyPath)'
                    """,
                    file: file,
                    line: line
                )
                return
            }

            if let nestedDictionary1 = value1 as? [String: Any],
               let nestedDictionary2 = value2 as? [String: Any] {
                AssertDictionariesEqual(
                    nestedDictionary1,
                    nestedDictionary2,
                    keyPath: currentKeyPath,
                    message: message,
                    file: file,
                    line: line
                )
            } else {
                let value1Description = String(describing: value1)
                let value2Description = String(describing: value2)
                XCTAssertEqual(
                    value1Description,
                    value2Description,
                    """
                    🔥 Failure: \(message)

                    The value for key path '\(currentKeyPath)' is different in both dictionaries:
                        * (1): \(value1Description)
                        * (2): \(value2Description)
                    """,
                    file: file,
                    line: line
                )
            }
        }
    }

    /// Asserts that JSON representations of two `Encodable` values are equal.
    /// This allows us testing if the information is not lost due to type erasing done in `CrashContext` serialization.
    func AssertEncodedRepresentationsEqual<V: Encodable>(
        value1: V,
        value2: V,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let prettyEncoder = JSONEncoder()
        prettyEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encodedValue1 = try prettyEncoder.encode(value1)
        let encodedValue2 = try prettyEncoder.encode(value2)

        let value1JSONString = encodedValue1.utf8String
        let value2JSONString = encodedValue2.utf8String
        XCTAssertEqual(value1JSONString, value2JSONString, file: file, line: line)
    }

    func AssertURLSessionTasksIdentical(
        _ actualTask: URLSessionTask,
        _ expectedTask: URLSessionTask,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            actualTask === expectedTask,
            """
            Both tasks must be identical ('===').

            Actual task:
            \(actualTask.dump())

            Expected task:
            \(expectedTask.dump())
            """,
            file: file,
            line: line
        )
    }
}
