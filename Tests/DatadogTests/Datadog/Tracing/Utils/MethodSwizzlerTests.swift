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
        MethodSwizzler.shared.unswizzleALL()
    }

    func test_simpleSwizzle() {
        let obj = BaseClass()

        // before
        XCTAssertNotEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, String.mockAny())
        // swizzle
        XCTAssertNoThrow(try swizzler.swizzleIfNonSwizzled(selector: selToSwizzle, in: BaseClass.self, with: newIMPReturnString))
        // after
        XCTAssertEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, String.mockAny())
    }

    func test_simpleUnswizzle() {
        try! swizzler.swizzleIfNonSwizzled(selector: selToSwizzle, in: BaseClass.self, with: newIMPReturnString)
        let obj = BaseClass()

        // before
        XCTAssertNotEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, BaseClass.returnValue)
        // unswizzle
        XCTAssertNoThrow(try swizzler.unswizzle(selector: selToSwizzle, in: BaseClass.self))
        // after
        XCTAssertEqual(obj.perform(selToSwizzle)?.takeUnretainedValue() as? String, BaseClass.returnValue)
    }

    func test_swizzleWrongSelector() {
        let wrongSelName = "selector_who_never_existed"
        let wrongSelToSwizzle = Selector(wrongSelName)

        let expectedError = SwizzlingError.methodNotFound(selector: wrongSelName, className: NSStringFromClass(BaseClass.self))
        XCTAssertThrowsError(
            try swizzler.swizzleIfNonSwizzled(selector: wrongSelToSwizzle, in: BaseClass.self, with: newIMPReturnString),
            "Unfound selector should throw"
        ) { err in
            XCTAssertEqual((err as? SwizzlingError), expectedError)
        }
    }

    func test_swizzleAlreadySwizzledSelector() {
        let expectedError = SwizzlingError.methodIsAlreadySwizzled(
            selector: NSStringFromSelector(selToSwizzle),
            targetClassName: NSStringFromClass(BaseClass.self),
            swizzledClassName: NSStringFromClass(BaseClass.self)
        )
        try! swizzler.swizzleIfNonSwizzled(selector: selToSwizzle, in: BaseClass.self, with: newIMPReturnString)

        XCTAssertThrowsError(
            try swizzler.swizzleIfNonSwizzled(selector: selToSwizzle, in: BaseClass.self, with: newIMPReturnString),
            "Already swizzled selector should throw"
        ) { err in
            XCTAssertEqual((err as? SwizzlingError), expectedError)
        }
    }

    func test_swizzleSubclass() {
        try! swizzler.swizzleIfNonSwizzled(selector: selToSwizzle, in: BaseClass.self, with: newIMPReturnString)
        let expectedError = SwizzlingError.methodIsAlreadySwizzled(
            selector: NSStringFromSelector(selToSwizzle),
            targetClassName: NSStringFromClass(EmptySubclass.self),
            swizzledClassName: NSStringFromClass(BaseClass.self)
        )

        XCTAssertThrowsError(
            try swizzler.swizzleIfNonSwizzled(
                selector: selToSwizzle,
                in: EmptySubclass.self,
                with: newIMPReturnString
            ), "foo"
        ) { err in
            XCTAssertEqual(err as? SwizzlingError, expectedError)
        }
    }

    func test_lazyEvaluationOfNewIMP() {
        let wrongSelToSwizzle = Selector(("selector_who_never_existed"))
        let newIMPProvider: () -> IMP = {
            XCTFail("New IMP should not be created after error")
            let block = { }
            return imp_implementationWithBlock(block)
        }

        XCTAssertThrowsError(
            try swizzler.swizzleIfNonSwizzled(selector: wrongSelToSwizzle, in: BaseClass.self, with: newIMPProvider())
        )
    }

    func test_unswizzleNonSwizzledSelector() {
        let selName = NSStringFromSelector(selToSwizzle)

        let expectedError = SwizzlingError.methodWasNotSwizzled(selector: selName, className: NSStringFromClass(BaseClass.self))
        XCTAssertThrowsError(
            try swizzler.unswizzle(selector: selToSwizzle, in: BaseClass.self),
            "Unswizzling a non-swizzled method should throw"
        ) { err in
            XCTAssertEqual((err as? SwizzlingError), expectedError)
        }
    }

    func test_parityCurrentOriginalIMP() {
        // before
        let beforeOrigIMP: IMP = try! swizzler.originalImplementation(of: selToSwizzle, in: BaseClass.self)
        let beforeCurrentIMP: IMP = try! swizzler.currentImplementation(of: selToSwizzle, in: BaseClass.self)
        // swizzle
        try! swizzler.swizzleIfNonSwizzled(selector: selToSwizzle, in: BaseClass.self, with: newIMPReturnString)
        // after
        let afterOrigIMP: IMP = try! swizzler.originalImplementation(of: selToSwizzle, in: BaseClass.self)
        let afterCurrentIMP: IMP = try! swizzler.currentImplementation(of: selToSwizzle, in: BaseClass.self)

        // unswizzle
        XCTAssertNoThrow(try swizzler.unswizzle(selector: selToSwizzle, in: BaseClass.self))
        // after unswizzle
        let unswizzledOrigIMP: IMP = try! swizzler.originalImplementation(of: selToSwizzle, in: BaseClass.self)
        let unswizzledCurrentIMP: IMP = try! swizzler.currentImplementation(of: selToSwizzle, in: BaseClass.self)

        XCTAssertEqual(beforeOrigIMP, beforeCurrentIMP)
        XCTAssertEqual(beforeOrigIMP, afterOrigIMP)
        XCTAssertNotEqual(afterOrigIMP, afterCurrentIMP)

        XCTAssertEqual(beforeOrigIMP, unswizzledOrigIMP)
        XCTAssertEqual(beforeCurrentIMP, unswizzledCurrentIMP)
    }
}
