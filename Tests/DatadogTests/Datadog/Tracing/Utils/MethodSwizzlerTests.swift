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
    private typealias TypedBlockReturnString = @convention(block) (AnyObject) -> String
    private let selToSwizzle = #selector(BaseClass.methodToSwizzle)
    private let newIMPReturnString: IMP = {
        let newBlockImp: TypedBlockReturnString = { _ in String.mockAny() }
        return imp_implementationWithBlock(newBlockImp)
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
        swizzler.set(newIMP: newIMPReturnString, for: foundMethod!)
        // after
        XCTAssertEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, String.mockAny())
    }

    func test_simpleUnswizzle() {
        let foundMethod = swizzler.findMethodRecursively(with: selToSwizzle, in: BaseClass.self)
        XCTAssertNotNil(foundMethod)
        swizzler.set(newIMP: newIMPReturnString, for: foundMethod!)

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
        swizzler.set(newIMP: newIMPReturnString, for: foundMethod)

        let secondSwizzlingReturnValue = "Second swizzling"
        let newImp: IMP = {
            let newBlockImp: TypedBlockReturnString = { _ in secondSwizzlingReturnValue }
            return imp_implementationWithBlock(newBlockImp)
        }()
        swizzler.set(newIMP: newImp, for: foundMethod)

        let afterOrigIMP: IMP = swizzler.originalImplementation(of: foundMethod)

        let obj = BaseClass()
        XCTAssertEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, secondSwizzlingReturnValue)
        XCTAssertEqual(beforeOrigIMP, afterOrigIMP)
    }

    func test_swizzleIfNonSwizzled_alreadySwizzledSelector() {
        let foundMethod = swizzler.findMethodRecursively(with: selToSwizzle, in: BaseClass.self)!
        // first swizzling
        swizzler.set(newIMP: newIMPReturnString, for: foundMethod)

        let secondSwizzlingReturnValue = "Second swizzling"
        let newImp: () -> IMP = {
            let newBlockImp: TypedBlockReturnString = { _ in secondSwizzlingReturnValue }
            return imp_implementationWithBlock(newBlockImp)
        }
        XCTAssertFalse(
            swizzler.swizzleIfNonSwizzled(foundMethod: foundMethod, with: newImp()),
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
        swizzler.set(newIMP: newIMPReturnString, for: foundMethod)

        let newImp: () -> IMP = {
            XCTFail("New IMP should not be created after error")
            let newBlockImp: TypedBlockReturnString = { _ in "" }
            return imp_implementationWithBlock(newBlockImp)
        }
        XCTAssertFalse(
            swizzler.swizzleIfNonSwizzled(foundMethod: foundMethod, with: newImp()),
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
        let beforeCurrentIMP: IMP = swizzler.currentImplementation(of: foundMethod)
        // swizzle
        swizzler.set(newIMP: newIMPReturnString, for: foundMethod)
        // after
        let afterOrigIMP: IMP = swizzler.originalImplementation(of: foundMethod)
        let afterCurrentIMP: IMP = swizzler.currentImplementation(of: foundMethod)

        // unswizzle
        XCTAssertTrue(swizzler.unsafe_unswizzle(foundMethod))
        // after unswizzle
        let unswizzledOrigIMP: IMP = swizzler.originalImplementation(of: foundMethod)
        let unswizzledCurrentIMP: IMP = swizzler.currentImplementation(of: foundMethod)

        XCTAssertEqual(beforeOrigIMP, beforeCurrentIMP)
        XCTAssertEqual(beforeOrigIMP, afterOrigIMP)
        XCTAssertNotEqual(afterOrigIMP, afterCurrentIMP)

        XCTAssertEqual(beforeOrigIMP, unswizzledOrigIMP)
        XCTAssertEqual(beforeCurrentIMP, unswizzledCurrentIMP)
    }
}
