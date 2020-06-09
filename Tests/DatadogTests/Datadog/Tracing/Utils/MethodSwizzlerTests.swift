/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

@objcMembers
private class EmptySubclass: BaseClass { }

@objcMembers
private class BaseClass: NSObject {
    static let returnValue = "this is base class"
    func methodToSwizzle() -> String {
        return Self.returnValue
    }
}

class RecursiveMethodSwizzlerTests: XCTestCase {
    private typealias TypedIMPReturnString = @convention(c) (AnyObject, Selector) -> String
    private typealias TypedBlockIMPReturnString = @convention(block) (AnyObject) -> String
    private let selToSwizzle = #selector(BaseClass.methodToSwizzle)
    private let newIMPReturnString: TypedBlockIMPReturnString = { _ in String.mockAny() }

    private let swizzler = MethodSwizzler.shared

    override func tearDown() {
        super.tearDown()
        MethodSwizzler.shared.unsafe_unswizzleALL()
    }

    func test_simpleSwizzle() throws {
        let obj = BaseClass()

        // before
        XCTAssertNotEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, String.mockAny())
        // swizzle
        let foundMethod = try swizzler.findMethod(with: selToSwizzle, in: BaseClass.self)
        swizzler.swizzle(foundMethod, impSignature: IMP.self) { _ in newIMPReturnString }
        // after
        XCTAssertEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, String.mockAny())
    }

    func test_searchWrongSelector() {
        let wrongSelToSwizzle = Selector(("selector_who_never_existed"))

        let expectedError = SwizzlingError.methodNotFound(
            selector: NSStringFromSelector(wrongSelToSwizzle),
            className: NSStringFromClass(BaseClass.self)
        )
        XCTAssertThrowsError(try swizzler.findMethod(with: wrongSelToSwizzle, in: BaseClass.self), "Wrong selector should throw") { err in
            XCTAssertEqual(err as? SwizzlingError, expectedError)
        }
    }

    func test_swizzle_alreadySwizzledSelector() throws {
        let foundMethod = try swizzler.findMethod(with: selToSwizzle, in: BaseClass.self)

        let beforeOrigIMP: IMP = swizzler.originalImplementation(of: foundMethod)
        // first swizzling
        swizzler.swizzle(foundMethod, impSignature: IMP.self) { _ in newIMPReturnString }

        let secondSwizzlingReturnValue = "Second swizzling"
        let newImp: TypedBlockIMPReturnString = { _ in secondSwizzlingReturnValue }
        swizzler.swizzle(foundMethod, impSignature: IMP.self) { _ in newImp }

        let afterOrigIMP: IMP = swizzler.originalImplementation(of: foundMethod)

        let obj = BaseClass()
        XCTAssertEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, secondSwizzlingReturnValue)
        XCTAssertEqual(beforeOrigIMP, afterOrigIMP)
    }

    func test_swizzleIfNonSwizzled_alreadySwizzledSelector() throws {
        let foundMethod = try swizzler.findMethod(with: selToSwizzle, in: BaseClass.self)
        // first swizzling
        swizzler.swizzle(foundMethod, impSignature: IMP.self) { _ in newIMPReturnString }

        let secondSwizzlingReturnValue = "Second swizzling"
        let newImp: TypedBlockIMPReturnString = { _ in secondSwizzlingReturnValue }
        XCTAssertFalse(
            swizzler.swizzle(foundMethod, impSignature: IMP.self, impProvider: { _ in newImp }, onlyIfNonSwizzled: true),
            "Already swizzled method should not be swizzled again"
        )

        let obj = BaseClass()
        XCTAssertNotEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, secondSwizzlingReturnValue)
    }

    func test_findSubclassMethod() throws {
        let subclassMethod = try swizzler.findMethod(with: selToSwizzle, in: EmptySubclass.self)

        XCTAssertNotNil(subclassMethod)
        XCTAssertEqual(NSStringFromClass(subclassMethod.klass), NSStringFromClass(BaseClass.self))
    }

    func test_lazyEvaluationOfNewIMP() throws {
        let foundMethod = try swizzler.findMethod(with: selToSwizzle, in: BaseClass.self)
        // first swizzling
        swizzler.swizzle(foundMethod, impSignature: IMP.self) { _ in newIMPReturnString }

        XCTAssertFalse(
            swizzler.swizzle(
                foundMethod,
                impSignature: IMP.self,
                impProvider: { _ -> TypedBlockIMPReturnString in
                    XCTFail("New IMP should not be created after error")
                    return newIMPReturnString
                },
                onlyIfNonSwizzled: true
            ),
            "Already swizzled method should not be swizzled again"
        )
    }

    func test_parityCurrentOriginalIMP() throws {
        let foundMethod = try swizzler.findMethod(with: selToSwizzle, in: BaseClass.self)

        // before
        let beforeOrigIMP: IMP = swizzler.originalImplementation(of: foundMethod)
        let beforeCurrentIMP: IMP = method_getImplementation(foundMethod.method)
        // swizzle
        swizzler.swizzle(foundMethod, impSignature: IMP.self) { currentTypedImp -> TypedBlockIMPReturnString in
            XCTAssertEqual(currentTypedImp, beforeCurrentIMP)
            return { _ in "first" }
        }
        // after
        let afterOrigIMP: IMP = swizzler.originalImplementation(of: foundMethod)
        let afterCurrentIMP: IMP = method_getImplementation(foundMethod.method)
        swizzler.swizzle(foundMethod, impSignature: IMP.self) { currentTypedImp -> TypedBlockIMPReturnString in
            XCTAssertEqual(currentTypedImp, afterCurrentIMP)
            return { _ in "second" }
        }

        XCTAssertEqual(beforeOrigIMP, beforeCurrentIMP)
        XCTAssertEqual(beforeOrigIMP, afterOrigIMP)
        XCTAssertNotEqual(afterOrigIMP, afterCurrentIMP)
    }

    func test_swizzleFromMultipleThreads() throws {
        let selector = selToSwizzle
        let foundMethod = try swizzler.findMethod(with: selector, in: BaseClass.self)

        let appendString = "swizzled"
        let iterCount = 10
        let expectation = self.expectation(description: "concurrent expectation")
        expectation.expectedFulfillmentCount = iterCount

        DispatchQueue.concurrentPerform(iterations: iterCount) { _ in
            swizzler.swizzle(
                foundMethod,
                impSignature: TypedIMPReturnString.self,
                impProvider: { originalImp -> TypedBlockIMPReturnString in
                    return { impSelf -> String in
                        return originalImp(impSelf, selector).appending(appendString)
                    }
                },
                onlyIfNonSwizzled: true
            )
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.1) { err in
            XCTAssertNil(err)

            let returnValue = BaseClass().perform(selector)?.takeUnretainedValue() as? String
            XCTAssertEqual(returnValue, "\(BaseClass.returnValue)\(appendString)")
        }
    }
}
