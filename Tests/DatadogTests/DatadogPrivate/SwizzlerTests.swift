/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import XCTest
import _Datadog_Private

private let dummyDescription = "DummySubclass description"

@objcMembers
private class DummySubclass: NSObject {
    override var description: String { dummyDescription }
}

@objcMembers
private class DummySubclassWithIvars: NSObject {
    let prop1: String = "prop1"
    let prop2: String = "prop2"
    let prop3: String = "prop3"
    override var description: String { dummyDescription }
}

class SwizzlerTests: XCTestCase {
    func testSwizzleSimpleObject() {
        let obj = NSObject()
        try! Swizzler.swizzle(obj, with: DummySubclass.self)

        XCTAssertEqual(obj.description, dummyDescription)
    }

    func testSwizzleWithWrongInstanceSize() {
        let obj = NSObject()
        do {
            try Swizzler.swizzle(obj, with: DummySubclassWithIvars.self)
        } catch {
            XCTAssertNotNil(error)
        }

        XCTAssertNotEqual(obj.description, dummyDescription)
    }

    func testUnswizzleSimpleObject() {
        let obj = NSObject()
        do {
            try Swizzler.unswizzle(obj, ifPrefixed: nil, andDisposeDynamicClass: false)
            XCTFail("Unswizzling non-swizzled object should throw")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func testUnswizzleSwizzledObject() {
        let obj = NSObject()
        try! Swizzler.swizzle(obj, with: DummySubclass.self)
        do {
            try Swizzler.unswizzle(obj, ifPrefixed: nil, andDisposeDynamicClass: false)
        } catch {
            XCTAssertNil(error)
        }
    }

    func testUnswizzleObjectWithWrongPrefix() {
        let obj = NSObject()
        try! Swizzler.swizzle(obj, with: DummySubclass.self)
        do {
            try Swizzler.unswizzle(obj, ifPrefixed: "wrong_prefix", andDisposeDynamicClass: false)
            XCTFail("Wrong prefix should throw")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func testSimpleClassCreation() {
        let newClass: AnyClass?
        newClass = Swizzler.dynamicClass(
            with: "SwizzlerTests_",
            superclass: NSObject.self
        ) { _ in
            return true
        }

        XCTAssertNotNil(newClass, "New class should be created successfully")
    }

    func testClassLookup() {
        var firstClassConfigured = false
        var secondClassConfigured = false

        let newClass: AnyClass?
        newClass = Swizzler.dynamicClass(
            with: "SwizzlerTests_",
            superclass: NSObject.self
        ) { _ in
            firstClassConfigured = true
            return true
        }

        let lookedUpClass: AnyClass?
        lookedUpClass = Swizzler.dynamicClass(
            with: "SwizzlerTests_",
            superclass: NSObject.self
        ) { _ in
            secondClassConfigured = true
            return true
        }

        defer {
            objc_disposeClassPair(lookedUpClass!)
        }

        XCTAssertNotNil(newClass)
        XCTAssertNotNil(lookedUpClass)
        XCTAssertTrue(firstClassConfigured)
        XCTAssertFalse(secondClassConfigured)
    }

    func testConfigurationFailure() {
        var firstClassConfigured = false
        var secondClassConfigured = false

        let firstClass: AnyClass?
        firstClass = Swizzler.dynamicClass(
            with: "SwizzlerTests_",
            superclass: NSObject.self
        ) { _ in
            firstClassConfigured = true
            return false
        }

        let secondClass: AnyClass?
        secondClass = Swizzler.dynamicClass(
            with: "SwizzlerTests_",
            superclass: NSObject.self
        ) { _ in
            secondClassConfigured = true
            return true
        }

        defer {
            objc_disposeClassPair(secondClass!)
        }

        XCTAssertNil(firstClass)
        XCTAssertNotNil(secondClass)
        XCTAssertTrue(firstClassConfigured)
        XCTAssertTrue(secondClassConfigured)
    }

// TODO: RUMM-300
//    + (BOOL)addMethodsOf:(Class)templateClass
//                      to:(Class)newClass
//                   error:(NSError **)error;

//    + (BOOL)setBlock:(id)blockIMP
//    implementationOf:(SEL)selector
//             inClass:(Class)klass
//               error:(NSError **)error;
}
