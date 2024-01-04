/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

@objc
private class BaseClass: NSObject {
    @objc
    func methodToSwizzle() -> String {
        "original"
    }
}

private class Swizzler: MethodSwizzler<@convention(c) (AnyObject, Selector) -> String, @convention(block) (AnyObject) -> String> {
    static let selector = #selector(BaseClass.methodToSwizzle)

    let method: Method

    init(method: Method) {
        self.method = method
    }

    init(_ cls: BaseClass.Type = BaseClass.self, _ name: Selector = Swizzler.selector) throws {
        method = try dd_class_getInstanceMethod(cls, name)
    }

    func swizzle(callback: @escaping () -> Void) {
        self.swizzle(method) { currentImp in
            return { impSelf in
                callback()
                return currentImp(impSelf, Swizzler.selector)
            }
        }
    }

    func swizzle(override: @escaping (String) -> String) {
        self.swizzle(method) { currentImp in
            return { impSelf in
                return override(currentImp(impSelf, Swizzler.selector))
            }
        }
    }
}

class MethodSwizzlerTests: XCTestCase {
    func test_simpleSwizzle() throws {
        let swizzler = try Swizzler()
        let obj = BaseClass()

        // before
        XCTAssertEqual(obj.perform(Swizzler.selector)?.takeUnretainedValue() as? String, "original")

        // swizzle
        swizzler.swizzle { $0 + .mockAny() }

        // after
        XCTAssertEqual(obj.perform(Swizzler.selector)?.takeUnretainedValue() as? String, "original" + .mockAny())
        swizzler.unswizzle()
    }

    func test_searchWrongSelector() {
        let wrongSelToSwizzle = Selector(("selector_who_never_existed"))

        let expectedErrorDescription = "\(NSStringFromSelector(wrongSelToSwizzle)) is not found in \(NSStringFromClass(BaseClass.self))"
        XCTAssertThrowsError(try dd_class_getInstanceMethod(BaseClass.self, wrongSelToSwizzle), "Wrong selector should throw") { error in
            let internalError = error as? InternalError
            XCTAssertEqual(internalError?.description, expectedErrorDescription)
        }
    }

    func test_findSubclassMethod() throws {
        class EmptySubclass: BaseClass { }
        class EmptySubSubclass: EmptySubclass { }
        XCTAssertNotNil(try dd_class_getInstanceMethod(EmptySubclass.self, Swizzler.selector))
        XCTAssertNotNil(try dd_class_getInstanceMethod(EmptySubSubclass.self, Swizzler.selector))
    }

    func test_multiple_swizzle() throws {
        let method = try dd_class_getInstanceMethod(BaseClass.self, Swizzler.selector)
        let swizzler1 = Swizzler(method: method)
        let swizzler2 = Swizzler(method: method)

        let obj = BaseClass()
        let before_imp = method_getImplementation(method)

        // first swizzling
        swizzler1.swizzle { $0 + ", first" }
        XCTAssertEqual(obj.perform(Swizzler.selector)?.takeUnretainedValue() as? String, "original, first")

        // second swizzling
        swizzler2.swizzle { $0 + ", second" }
        XCTAssertEqual(obj.perform(Swizzler.selector)?.takeUnretainedValue() as? String, "original, first, second")

        // third swizzling
        swizzler1.swizzle { $0 + ", third" }
        XCTAssertEqual(obj.perform(Swizzler.selector)?.takeUnretainedValue() as? String, "original, first, second, third")

        // remove second swizzling
        swizzler2.unswizzle()
        XCTAssertEqual(obj.perform(Swizzler.selector)?.takeUnretainedValue() as? String, "original, first, third")

        // revert to original imp
        swizzler1.unswizzle()
        let after_imp = method_getImplementation(method)
        XCTAssertEqual(obj.perform(Swizzler.selector)?.takeUnretainedValue() as? String, "original")
        XCTAssertEqual(before_imp, after_imp)
    }

    func test_swizzle_count() throws {
        class Subclass: BaseClass {
            override func methodToSwizzle() -> String { "subclass" }
        }
        class SubSubclass: Subclass {
            override func methodToSwizzle() -> String { "subsubclass" }
        }

        // Given
        let method1 = try dd_class_getInstanceMethod(BaseClass.self, Swizzler.selector)
        let method2 = try dd_class_getInstanceMethod(Subclass.self, Swizzler.selector)
        let method3 = try dd_class_getInstanceMethod(SubSubclass.self, Swizzler.selector)

        let swizzler1 = Swizzler(method: method1)
        let swizzler2 = Swizzler(method: method2)
        let swizzler3 = Swizzler(method: method3)

        // When
        swizzler1.swizzle { }
        XCTAssertEqual(Swizzling.methods.count, 1)
        swizzler2.swizzle { }
        XCTAssertEqual(Swizzling.methods.count, 2)
        swizzler3.swizzle { }
        XCTAssertEqual(Swizzling.methods.count, 3)

        // Then
        XCTAssertEqual(Swizzling.description, "[methodToSwizzle, methodToSwizzle, methodToSwizzle]")

        // When
        swizzler1.unswizzle()
        XCTAssertEqual(Swizzling.methods.count, 2)
        swizzler2.unswizzle()
        XCTAssertEqual(Swizzling.methods.count, 1)
        swizzler3.unswizzle()
        XCTAssertEqual(Swizzling.methods.count, 0)

        // Then
        XCTAssertEqual(Swizzling.description, "[]")
    }

    func test_swizzle_concurrently() throws {
        // swiftlint:disable opening_brace

        // Given
        let method = try dd_class_getInstanceMethod(BaseClass.self, Swizzler.selector)
        let swizzler1 = Swizzler(method: method)
        let swizzler2 = Swizzler(method: method)
        let swizzler3 = Swizzler(method: method)

        let before_imp = method_getImplementation(method)
        var callstack: [String] = []

        // When
        callConcurrently(
            { swizzler1.swizzle { callstack.append("1.1") } },
            { swizzler1.swizzle { callstack.append("1.2") } },
            { swizzler2.swizzle { callstack.append("2") } },
            { swizzler3.swizzle { callstack.append("3") } }
        )

        // Then
        let obj = BaseClass()
        XCTAssertEqual(obj.perform(Swizzler.selector)?.takeUnretainedValue() as? String, "original")

        callstack.sort()
        XCTAssertEqual(callstack, ["1.1", "1.2", "2", "3"])

        // When
        callstack = []
        callConcurrently(
            { swizzler1.unswizzle() },
            { swizzler2.unswizzle() },
            { swizzler3.unswizzle() }
        )
        XCTAssertEqual(obj.perform(Swizzler.selector)?.takeUnretainedValue() as? String, "original")
        XCTAssertEqual(callstack, [])

        let after_imp = method_getImplementation(method)
        XCTAssertEqual(before_imp, after_imp)
        // swiftlint:enable opening_brace
    }
}
