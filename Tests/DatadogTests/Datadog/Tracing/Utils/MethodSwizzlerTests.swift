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

@objcMembers
private class NonNSObjectSubclass {
    static let returnValue = "this is base class"

    func methodToSwizzle() -> String {
        return Self.returnValue
    }
}

private class ThirdPartySwizzler {
    private var originalIMP: IMP? = nil
    private let selector: Selector = #selector(BaseClass.methodToSwizzle)
    private let targetClass: AnyClass = BaseClass.self

    func swizzleMethodToSwizzle() {
        typealias TypedIMP = @convention(c) (AnyObject, Selector) -> String
        typealias TypedBlockIMP = @convention(block) (AnyObject) -> String

        let method: Method = class_getInstanceMethod(targetClass, selector)!
        let currentMethodImp: IMP = method_getImplementation(method)
        self.originalIMP = currentMethodImp

        let typedMethodImp: TypedIMP = unsafeBitCast(currentMethodImp, to: TypedIMP.self)
        let newBlockImp: TypedBlockIMP = { [originalImp = typedMethodImp, impSel = selector] impSelf -> String in
            let originalRetVal = originalImp(impSelf, impSel)
            return originalRetVal + "...3rd party swizzled"
        }
        let newImp = imp_implementationWithBlock(newBlockImp)
        method_setImplementation(method, newImp)
    }

    deinit {
        let method: Method = class_getInstanceMethod(targetClass, selector)!
        method_setImplementation(method, self.originalIMP!)
    }
}

class MethodSwizzlerTests: XCTestCase {
    private let swizzler = MethodSwizzler.shared

    func testSimpleSwizzling() {
        typealias TypedIMP = @convention(c) (AnyObject, Selector) -> String
        typealias TypedBlockIMP = @convention(block) (AnyObject) -> String

        let sel = #selector(BaseClass.methodToSwizzle as (BaseClass) -> () -> String)
        let newBlockImp: TypedBlockIMP = { impSelf -> String in
            return .mockAny()
        }
        let newImp = imp_implementationWithBlock(newBlockImp)

        let obj = BaseClass()

        XCTAssertNoThrow(try swizzler.swizzle(selector: sel, in: BaseClass.self, with: newImp))
        XCTAssertEqual(obj.perform(sel)?.takeUnretainedValue() as? String, String.mockAny())
    }

    func testUnswizzling() {
        typealias TypedIMP = @convention(c) (AnyObject, Selector) -> String
        typealias TypedBlockIMP = @convention(block) (AnyObject) -> String

        let sel = #selector(BaseClass.methodToSwizzle as (BaseClass) -> () -> String)
        let newBlockImp: TypedBlockIMP = { impSelf -> String in
            return .mockAny()
        }
        let newImp = imp_implementationWithBlock(newBlockImp)

        try! swizzler.swizzle(selector: sel, in: BaseClass.self, with: newImp)

        let obj = BaseClass()

        XCTAssertNoThrow(try swizzler.unswizzle(selector: sel, in: BaseClass.self))
        XCTAssertEqual(obj.perform(sel)?.takeUnretainedValue() as? String, BaseClass.returnValue)
    }

    func testSwizzleSuperclassMethod() {
        typealias TypedIMP = @convention(c) (AnyObject, Selector) -> String
        typealias TypedBlockIMP = @convention(block) (AnyObject) -> String

        let klass: AnyClass = EmptySubclass.self
        let sel = #selector(EmptySubclass.methodToSwizzle as (EmptySubclass) -> () -> String)
        let newBlockImp: TypedBlockIMP = { impSelf -> String in
            return .mockAny()
        }
        let newImp = imp_implementationWithBlock(newBlockImp)

        XCTAssertThrowsError(try swizzler.swizzle(selector: sel, in: klass, with: newImp), "Method should NOT be found") { error in
            guard case SwizzlingError.methodNotFound(let unfoundSelector, let searchedClassName) = error else {
                XCTFail("Expected `SwizzlingError.methodNotFound`: \(error)")
                return
            }
            XCTAssertEqual(unfoundSelector, NSStringFromSelector(sel))
            XCTAssertEqual(searchedClassName, NSStringFromClass(klass))
        }
    }

    func testSwizzleNonNSObjectSubclass() {
        typealias TypedIMP = @convention(c) (AnyObject, Selector) -> String
        typealias TypedBlockIMP = @convention(block) (AnyObject) -> String

        let klass: AnyClass = NonNSObjectSubclass.self
        let sel = #selector(NonNSObjectSubclass.methodToSwizzle as (NonNSObjectSubclass) -> () -> String)
        let newBlockImp: TypedBlockIMP = { impSelf -> String in
            return .mockAny()
        }
        let newImp = imp_implementationWithBlock(newBlockImp)

        XCTAssertThrowsError(try swizzler.swizzle(selector: sel, in: klass, with: newImp), "Method should NOT be found") { error in
            guard case SwizzlingError.classIsNotNSObjectSubclass(let className) = error else {
                XCTFail("Expected `SwizzlingError.classIsNotNSObjectSubclass`: \(error)")
                return
            }
            XCTAssertEqual(className, NSStringFromClass(klass))
        }
    }

    func testThirdPartySwizzling() {
        typealias TypedIMP = @convention(c) (AnyObject, Selector) -> String
        typealias TypedBlockIMP = @convention(block) (AnyObject) -> String

        let sel = #selector(BaseClass.methodToSwizzle as (BaseClass) -> () -> String)
        let newBlockImp: TypedBlockIMP = { impSelf -> String in
            return .mockAny()
        }
        let newImp = imp_implementationWithBlock(newBlockImp)

        let obj = BaseClass()

        try! swizzler.swizzle(selector: sel, in: BaseClass.self, with: newImp)

        let thirdPartySwizzler = ThirdPartySwizzler()
        thirdPartySwizzler.swizzleMethodToSwizzle()

        let returnValue: String = obj.perform(sel)?.takeUnretainedValue() as! String
        XCTAssertNotEqual(returnValue, String.mockAny())
        XCTAssert(returnValue.contains(String.mockAny()))
    }
}
