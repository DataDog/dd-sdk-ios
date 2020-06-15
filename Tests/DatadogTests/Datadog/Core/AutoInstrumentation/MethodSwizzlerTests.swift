/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

extension MethodSwizzler {
    func unswizzle() {
        for foundMethod in swizzledMethods {
            let originalTypedIMP = originalImplementation(of: foundMethod)
            let originalIMP: IMP = unsafeBitCast(originalTypedIMP, to: IMP.self)
            method_setImplementation(foundMethod.method, originalIMP)
        }
    }
}

@objcMembers
private class EmptySubclass: BaseClass { }

@objcMembers
private class BaseClass: NSObject {
    static let returnValue = "this is base class"
    func methodToSwizzle() -> String {
        return Self.returnValue
    }
}

class MethodSwizzlerTests: XCTestCase {
    private typealias TypedIMPReturnString = @convention(c) (AnyObject, Selector) -> String
    private typealias TypedBlockIMPReturnString = @convention(block) (AnyObject) -> String

    private let selToSwizzle = #selector(BaseClass.methodToSwizzle)
    private let newIMPReturnString: TypedBlockIMPReturnString = { _ in String.mockAny() }

    private typealias Swizzler = MethodSwizzler<TypedIMPReturnString, TypedBlockIMPReturnString>
    private let swizzler = try! Swizzler()

    override func tearDown() {
        super.tearDown()
        swizzler.unswizzle()
    }

    func test_simpleSwizzle() throws {
        let obj = BaseClass()

        // before
        XCTAssertNotEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, String.mockAny())
        // swizzle
        let foundMethod = try Swizzler.findMethod(with: selToSwizzle, in: BaseClass.self)
        swizzler.swizzle(foundMethod) { currentImp -> TypedBlockIMPReturnString in
            return { impSelf in
                return currentImp(impSelf, self.selToSwizzle).appending(String.mockAny())
            }
        }
        // after
        XCTAssertEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, BaseClass.returnValue + String.mockAny())
    }

    func test_searchWrongSelector() {
        let wrongSelToSwizzle = Selector(("selector_who_never_existed"))

        let expectedErrorDescription = "\(NSStringFromSelector(wrongSelToSwizzle)) is not found in \(NSStringFromClass(BaseClass.self))"
        XCTAssertThrowsError(try Swizzler.findMethod(with: wrongSelToSwizzle, in: BaseClass.self), "Wrong selector should throw") { error in
            let internalError = error as? InternalError
            XCTAssertEqual(internalError?.description, expectedErrorDescription)
        }
    }

    func test_swizzle_alreadySwizzledSelector() throws {
        let foundMethod = try Swizzler.findMethod(with: selToSwizzle, in: BaseClass.self)

        let beforeOrigTypedIMP = swizzler.originalImplementation(of: foundMethod)
        // first swizzling
        let firstAppendedReturnValue = "first"
        swizzler.swizzle(foundMethod) { currentImp -> TypedBlockIMPReturnString in
            return { impSelf in
                return currentImp(impSelf, self.selToSwizzle).appending(firstAppendedReturnValue)
            }
        }

        let secondAppendedReturnValue = "second"
        swizzler.swizzle(foundMethod) { currentImp -> TypedBlockIMPReturnString in
            return { impSelf in
                return currentImp(impSelf, self.selToSwizzle).appending(secondAppendedReturnValue)
            }
        }

        let afterOrigTypedIMP = swizzler.originalImplementation(of: foundMethod)

        let obj = BaseClass()
        let expectedReturnValue = BaseClass.returnValue + firstAppendedReturnValue + secondAppendedReturnValue
        XCTAssertEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, expectedReturnValue)
        XCTAssertEqual(
            unsafeBitCast(beforeOrigTypedIMP, to: IMP.self),
            unsafeBitCast(afterOrigTypedIMP, to: IMP.self)
        )
    }

    func test_swizzleIfNonSwizzled_alreadySwizzledSelector() throws {
        let foundMethod = try Swizzler.findMethod(with: selToSwizzle, in: BaseClass.self)
        // first swizzling
        swizzler.swizzle(foundMethod) { _ in newIMPReturnString }

        let secondSwizzlingReturnValue = "Second swizzling"
        let newImp: TypedBlockIMPReturnString = { _ in secondSwizzlingReturnValue }
        XCTAssertFalse(
            swizzler.swizzle(foundMethod, impProvider: { _ in newImp }, onlyIfNonSwizzled: true),
            "Already swizzled method should not be swizzled again"
        )

        let obj = BaseClass()
        XCTAssertNotEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, secondSwizzlingReturnValue)
    }

    func test_findSubclassMethod() throws {
        let subclassMethod = try Swizzler.findMethod(with: selToSwizzle, in: EmptySubclass.self)

        XCTAssertNotNil(subclassMethod)
        XCTAssertEqual(NSStringFromClass(subclassMethod.klass), NSStringFromClass(BaseClass.self))
    }

    func test_lazyEvaluationOfNewIMP() throws {
        let foundMethod = try Swizzler.findMethod(with: selToSwizzle, in: BaseClass.self)
        // first swizzling
        swizzler.swizzle(foundMethod) { _ in newIMPReturnString }

        XCTAssertFalse(
            swizzler.swizzle(
                foundMethod,
                impProvider: { _ -> TypedBlockIMPReturnString in
                    XCTFail("New IMP should not be created after error")
                    return newIMPReturnString
                },
                onlyIfNonSwizzled: true
            ),
            "Already swizzled method should not be swizzled again"
        )
    }

    func test_originalIMP_immutability() throws {
        let foundMethod = try Swizzler.findMethod(with: selToSwizzle, in: BaseClass.self)

        // first swizzling
        swizzler.swizzle(foundMethod) { _ -> TypedBlockIMPReturnString in
            return { _ in
                "first"
            }
        }
        // second swizzling
        swizzler.swizzle(foundMethod) { _ -> TypedBlockIMPReturnString in
            return { _ in
                "second"
            }
        }

        // revert to original imp
        let originalTypedImp = swizzler.originalImplementation(of: foundMethod)
        let originalImp = unsafeBitCast(originalTypedImp, to: IMP.self)
        method_setImplementation(foundMethod.method, originalImp)

        let obj = BaseClass()
        let expectedReturnValue = BaseClass.returnValue
        XCTAssertEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, expectedReturnValue)
    }

    func test_swizzleFromMultipleThreads() throws {
        let selector = selToSwizzle
        let foundMethod = try Swizzler.findMethod(with: selector, in: BaseClass.self)

        let appendString = "swizzled"
        let iterations = 10
        let expectation = self.expectation(description: "concurrent expectation")
        expectation.expectedFulfillmentCount = iterations

        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            swizzler.swizzle(
                foundMethod,
                impProvider: { originalImp -> TypedBlockIMPReturnString in
                    return { impSelf -> String in
                        return originalImp(impSelf, selector).appending(appendString)
                    }
                },
                onlyIfNonSwizzled: true
            )
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.1) { error in
            XCTAssertNil(error)

            let returnValue = BaseClass().perform(selector)?.takeUnretainedValue() as? String
            XCTAssertEqual(returnValue, "\(BaseClass.returnValue)\(appendString)")
        }
    }
}
