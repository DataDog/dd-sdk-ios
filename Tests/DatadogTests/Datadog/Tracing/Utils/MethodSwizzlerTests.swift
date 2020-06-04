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
    private let newIMPReturnString: IMP = {
        let blockIMP: TypedBlockIMPReturnString = { _ in String.mockAny() }
        return imp_implementationWithBlock(blockIMP)
    }()

    private let swizzler = MethodSwizzler.shared

    override func tearDown() {
        super.tearDown()
        MethodSwizzler.shared.unsafe_unswizzleALL()
    }

    func test_simpleSwizzle() {
        let obj = BaseClass()

        // before
        XCTAssertNotEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, String.mockAny())
        // swizzle
        let foundMethod = swizzler.findMethodRecursively(with: selToSwizzle, in: BaseClass.self)
        XCTAssertNotNil(foundMethod)
        swizzler.swizzle(foundMethod!, impSignature: IMP.self) { _ in newIMPReturnString }
        // after
        XCTAssertEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, String.mockAny())
    }

    func test_simpleUnswizzle() {
        let foundMethod = swizzler.findMethodRecursively(with: selToSwizzle, in: BaseClass.self)
        XCTAssertNotNil(foundMethod)
        swizzler.swizzle(foundMethod!, impSignature: IMP.self) { _ in newIMPReturnString }

        let obj = BaseClass()

        // before
        XCTAssertNotEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, BaseClass.returnValue)
        // unswizzle
        XCTAssertTrue(swizzler.unsafe_unswizzle(foundMethod!))
        // after
        XCTAssertEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, BaseClass.returnValue)
    }

    func test_searchWrongSelector() {
        let wrongSelToSwizzle = Selector(("selector_who_never_existed"))

        let unfoundMethod = swizzler.findMethodRecursively(with: wrongSelToSwizzle, in: BaseClass.self)

        XCTAssertNil(unfoundMethod)
    }

    func test_swizzle_alreadySwizzledSelector() {
        let foundMethod = swizzler.findMethodRecursively(with: selToSwizzle, in: BaseClass.self)!

        let beforeOrigIMP: IMP = swizzler.originalImplementation(of: foundMethod)
        // first swizzling
        swizzler.swizzle(foundMethod, impSignature: IMP.self) { _ in newIMPReturnString }

        let secondSwizzlingReturnValue = "Second swizzling"
        let newImp: IMP = {
            let block: TypedBlockIMPReturnString = { _ in secondSwizzlingReturnValue }
            return imp_implementationWithBlock(block)
        }()
        swizzler.swizzle(foundMethod, impSignature: IMP.self) { _ in newImp }

        let afterOrigIMP: IMP = swizzler.originalImplementation(of: foundMethod)

        let obj = BaseClass()
        XCTAssertEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, secondSwizzlingReturnValue)
        XCTAssertEqual(beforeOrigIMP, afterOrigIMP)
    }

    func test_swizzleIfNonSwizzled_alreadySwizzledSelector() {
        let foundMethod = swizzler.findMethodRecursively(with: selToSwizzle, in: BaseClass.self)!
        // first swizzling
        swizzler.swizzle(foundMethod, impSignature: IMP.self) { _ in newIMPReturnString }

        let secondSwizzlingReturnValue = "Second swizzling"
        let newImp: IMP = {
            let block: TypedBlockIMPReturnString = { _ in secondSwizzlingReturnValue }
            return imp_implementationWithBlock(block)
        }()
        XCTAssertFalse(
            swizzler.swizzle(foundMethod, impSignature: IMP.self, impProvider: { _ in newImp }, onlyIfNonSwizzled: true),
            "Already swizzled method should not be swizzled again"
        )

        let obj = BaseClass()
        XCTAssertNotEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, secondSwizzlingReturnValue)
    }

    func test_findSubclassMethod() {
        let subclassMethod = swizzler.findMethodRecursively(with: selToSwizzle, in: EmptySubclass.self)

        XCTAssertNotNil(subclassMethod)
        XCTAssertEqual(NSStringFromClass(subclassMethod!.klass), NSStringFromClass(BaseClass.self))
    }

    func test_lazyEvaluationOfNewIMP() {
        let foundMethod = swizzler.findMethodRecursively(with: selToSwizzle, in: BaseClass.self)!
        // first swizzling
        swizzler.swizzle(foundMethod, impSignature: IMP.self) { _ in newIMPReturnString }

        XCTAssertFalse(
            swizzler.swizzle(
                foundMethod,
                impSignature: IMP.self,
                impProvider: { _ -> IMP in
                    XCTFail("New IMP should not be created after error")
                    return newIMPReturnString
                },
                onlyIfNonSwizzled: true
            ),
            "Already swizzled method should not be swizzled again"
        )
    }

    func test_unswizzleNonSwizzledSelector() {
        let nonswizzledMethod = swizzler.findMethodRecursively(with: selToSwizzle, in: BaseClass.self)!

        let unswizzleResult = swizzler.unsafe_unswizzle(nonswizzledMethod)
        XCTAssertFalse(unswizzleResult, "Unswizzling a non-swizzled method should return false")
    }

    func test_parityCurrentOriginalIMP() {
        let foundMethod = swizzler.findMethodRecursively(with: selToSwizzle, in: BaseClass.self)!

        // before
        let beforeOrigIMP: IMP = swizzler.originalImplementation(of: foundMethod)
        let beforeCurrentIMP: IMP = method_getImplementation(foundMethod.method)
        // swizzle
        swizzler.swizzle(foundMethod, impSignature: IMP.self) { currentTypedImp -> IMP in
            XCTAssertEqual(currentTypedImp, beforeCurrentIMP)
            let block: TypedBlockIMPReturnString = { _ in "first" }
            return imp_implementationWithBlock(block)
        }
        // after
        let afterOrigIMP: IMP = swizzler.originalImplementation(of: foundMethod)
        let afterCurrentIMP: IMP = method_getImplementation(foundMethod.method)
        swizzler.swizzle(foundMethod, impSignature: IMP.self) { currentTypedImp -> IMP in
            XCTAssertEqual(currentTypedImp, afterCurrentIMP)
            let block: TypedBlockIMPReturnString = { _ in "second" }
            return imp_implementationWithBlock(block)
        }

        // unswizzle
        XCTAssertTrue(swizzler.unsafe_unswizzle(foundMethod))
        // after unswizzle
        let unswizzledOrigIMP: IMP = swizzler.originalImplementation(of: foundMethod)
        let unswizzledCurrentIMP: IMP = method_getImplementation(foundMethod.method)
        swizzler.swizzle(foundMethod, impSignature: IMP.self) { currentTypedImp -> IMP in
            XCTAssertEqual(currentTypedImp, unswizzledCurrentIMP)
            let block: TypedBlockIMPReturnString = { _ in "third" }
            return imp_implementationWithBlock(block)
        }

        XCTAssertEqual(beforeOrigIMP, beforeCurrentIMP)
        XCTAssertEqual(beforeOrigIMP, afterOrigIMP)
        XCTAssertNotEqual(afterOrigIMP, afterCurrentIMP)

        XCTAssertEqual(beforeOrigIMP, unswizzledOrigIMP)
        XCTAssertEqual(beforeCurrentIMP, unswizzledCurrentIMP)
    }
}
