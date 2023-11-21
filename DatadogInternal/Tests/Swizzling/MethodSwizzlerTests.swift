/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

@objc
private class BaseClass: NSObject {
    static let returnValue = "this is base class"

    @objc
    func methodToSwizzle() -> String {
        return Self.returnValue
    }
}

class MethodSwizzlerTests: XCTestCase {
    private typealias MethodSignature = @convention(c) (AnyObject, Selector) -> String
    private typealias MethodOverride = @convention(block) (AnyObject) -> String

    private let selToSwizzle = #selector(BaseClass.methodToSwizzle)

    private typealias Swizzler = MethodSwizzler<MethodSignature, MethodOverride>
    private let swizzler = Swizzler()

    override func tearDown() {
        swizzler.unswizzle()
        super.tearDown()
    }

    func test_simpleSwizzle() throws {
        let obj = BaseClass()

        // before
        XCTAssertNotEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, String.mockAny())
        // swizzle
        let foundMethod = try dd_sel_findMethod(selToSwizzle, in: BaseClass.self)
        swizzler.swizzle(foundMethod) { currentImp -> MethodOverride in
            return { impSelf in
                return currentImp(impSelf, self.selToSwizzle).appending(String.mockAny())
            }
        }
        // after
        XCTAssertEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, BaseClass.returnValue + String.mockAny())
        swizzler.unswizzle()
    }

    func test_searchWrongSelector() {
        let wrongSelToSwizzle = Selector(("selector_who_never_existed"))

        let expectedErrorDescription = "\(NSStringFromSelector(wrongSelToSwizzle)) is not found in \(NSStringFromClass(BaseClass.self))"
        XCTAssertThrowsError(try dd_sel_findMethod(wrongSelToSwizzle, in: BaseClass.self), "Wrong selector should throw") { error in
            let internalError = error as? InternalError
            XCTAssertEqual(internalError?.description, expectedErrorDescription)
        }
    }

    func test_findSubclassMethod() throws {
        class EmptySubclass: BaseClass { }
        let subclassMethod = try dd_sel_findMethod(selToSwizzle, in: EmptySubclass.self)
        XCTAssertNotNil(subclassMethod)
    }

    func test_swizzle_alreadySwizzledSelector() throws {
        let method = try dd_sel_findMethod(selToSwizzle, in: BaseClass.self)
        let obj = BaseClass()
        let before_imp = method_getImplementation(method)

        // first swizzling
        swizzler.swizzle(method) { _ -> MethodOverride in
            return { _ in "first" }
        }

        XCTAssertEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, "first")

        // second swizzling
        swizzler.swizzle(method) { _ -> MethodOverride in
            return { _ in "second" }
        }

        XCTAssertEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, "second")

        // revert to original imp
        swizzler.unswizzle()
        let after_imp = method_getImplementation(method)
        XCTAssertEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, BaseClass.returnValue)
        XCTAssertEqual(before_imp, after_imp)
    }

    func testMultipleSwizzlingConcurrently() throws {
        // swiftlint:disable opening_brace

        class Swizzler: MethodSwizzler<MethodSignature, MethodOverride> {
            static let selector = #selector(BaseClass.methodToSwizzle)

            let method: Method

            init(method: Method) {
                self.method = method
            }

            func swizzle(callback: @escaping () -> Void) {
                self.swizzle(method) { currentImp -> MethodOverride in
                    return { impSelf in
                        callback()
                        return currentImp(impSelf, Swizzler.selector)
                    }
                }
            }
        }

        // Given
        let method = try dd_sel_findMethod(Swizzler.selector, in: BaseClass.self)
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
        XCTAssertEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, BaseClass.returnValue)

        callstack.sort()
        XCTAssertEqual(callstack, ["1.1", "1.2", "2", "3"])

        // When
        callstack = []
        callConcurrently(
            { swizzler1.unswizzle() },
            { swizzler2.unswizzle() },
            { swizzler3.unswizzle() }
        )
        XCTAssertEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, BaseClass.returnValue)
        XCTAssertEqual(callstack, [])

        let after_imp = method_getImplementation(method)
        XCTAssertEqual(before_imp, after_imp)
        // swiftlint:enable opening_brace
    }
}
