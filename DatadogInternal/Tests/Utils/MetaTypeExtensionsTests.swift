/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

final class MetaTypeExtensionsTests: XCTestCase {
    func testKey() throws {
        // Prefix depends on the scheme which may be iOS or tvOS, hence only assert suffix.
        XCTAssertTrue(MetaTypeExtensions.key(from: TopLevelStruct.self).hasSuffix(".TopLevelStruct"))
        XCTAssertTrue(MetaTypeExtensions.key(from: TopLevelStruct.NestedStructInStruct.self).hasSuffix(".TopLevelStruct.NestedStructInStruct"))
        XCTAssertTrue(MetaTypeExtensions.key(from: TopLevelStruct.NestedClassInStruct.self).hasSuffix(".TopLevelStruct.NestedClassInStruct"))
        XCTAssertTrue(MetaTypeExtensions.key(from: TopLevelStruct.NestedEnumInStruct.self).hasSuffix(".TopLevelStruct.NestedEnumInStruct"))

        XCTAssertTrue(MetaTypeExtensions.key(from: TopLevelClass.self).hasSuffix(".TopLevelClass"))
        XCTAssertTrue(MetaTypeExtensions.key(from: TopLevelClass.NestedStructInClass.self).hasSuffix(".TopLevelClass.NestedStructInClass"))
        XCTAssertTrue(MetaTypeExtensions.key(from: TopLevelClass.NestedClassInClass.self).hasSuffix(".TopLevelClass.NestedClassInClass"))
        XCTAssertTrue(MetaTypeExtensions.key(from: TopLevelClass.NestedEnumInClass.self).hasSuffix(".TopLevelClass.NestedEnumInClass"))

        XCTAssertTrue(MetaTypeExtensions.key(from: TopLevelEnum.self).hasSuffix(".TopLevelEnum"))
        XCTAssertTrue(MetaTypeExtensions.key(from: TopLevelEnum.NestedStructInEnum.self).hasSuffix(".TopLevelEnum.NestedStructInEnum"))
        XCTAssertTrue(MetaTypeExtensions.key(from: TopLevelEnum.NestedClassInEnum.self).hasSuffix(".TopLevelEnum.NestedClassInEnum"))
        XCTAssertTrue(MetaTypeExtensions.key(from: TopLevelEnum.NestedEnumInEnum.self).hasSuffix(".TopLevelEnum.NestedEnumInEnum"))
    }
}

struct TopLevelStruct {
    struct NestedStructInStruct {}

    class NestedClassInStruct {}

    enum NestedEnumInStruct {}
}

class TopLevelClass {
    struct NestedStructInClass {}

    class NestedClassInClass {}

    enum NestedEnumInClass {}
}

enum TopLevelEnum {
    struct NestedStructInEnum {}

    class NestedClassInEnum {}

    enum NestedEnumInEnum {}
}
