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

        XCTAssertThrowsError(try Swizzler.swizzle(obj, with: DummySubclassWithIvars.self))
        XCTAssertNotEqual(obj.description, dummyDescription)
    }

    func testUnswizzleSimpleObject() {
        let obj = NSObject()

        XCTAssertThrowsError(try Swizzler.unswizzle(obj, ifPrefixed: nil, andDisposeDynamicClass: false))
    }

    func testUnswizzleSwizzledObject() {
        let obj = NSObject()
        try! Swizzler.swizzle(obj, with: DummySubclass.self)

        XCTAssertNoThrow(try Swizzler.unswizzle(obj, ifPrefixed: nil, andDisposeDynamicClass: false))
        XCTAssertNotEqual(obj.description, dummyDescription)
    }

    func testUnswizzleObjectWithWrongPrefix() {
        let obj = NSObject()
        try! Swizzler.swizzle(obj, with: DummySubclass.self)

        XCTAssertThrowsError(try Swizzler.unswizzle(obj, ifPrefixed: "wrong_prefix", andDisposeDynamicClass: false))
    }

    func testCreateMultipleDynamicClasses() {
        // swiftlint:disable multiline_arguments_brackets
        let fooPrefixedClass1: AnyClass? = Swizzler.createClass(
            with: "Foo",
            superclass: NSObject.self
        ) { _ in return true }
        let fooPrefixedClass2: AnyClass? = Swizzler.createClass(
            with: "Foo",
            superclass: NSObject.self
        ) { _ in return true }
        let fooPrefixedClass3: AnyClass? = Swizzler.createClass(
            with: "Foo",
            superclass: NSObject.self
        ) { _ in return true }

        let barPrefixedClass1: AnyClass? = Swizzler.createClass(
            with: "Bar",
            superclass: NSObject.self
        ) { _ in return true }
        let barPrefixedClass2: AnyClass? = Swizzler.createClass(
            with: "Bar",
            superclass: NSObject.self
        ) { _ in return true }
        // swiftlint:enable multiline_arguments_brackets

        defer {
            objc_disposeClassPair(fooPrefixedClass1!)
            objc_disposeClassPair(fooPrefixedClass2!)
            objc_disposeClassPair(fooPrefixedClass3!)
        }

        XCTAssertNotNil(fooPrefixedClass1)
        XCTAssertNotNil(fooPrefixedClass2)
        XCTAssertNotNil(fooPrefixedClass3)
        let fooClassName1 = NSStringFromClass(fooPrefixedClass1!)
        let fooClassName2 = NSStringFromClass(fooPrefixedClass2!)
        let fooClassName3 = NSStringFromClass(fooPrefixedClass3!)
        XCTAssertNotEqual(fooClassName1, fooClassName2)
        XCTAssertNotEqual(fooClassName1, fooClassName3)
        XCTAssertNotEqual(fooClassName2, fooClassName3)
        XCTAssertTrue(fooClassName1.hasPrefix("Foo"))
        XCTAssertTrue(fooClassName2.hasPrefix("Foo"))
        XCTAssertTrue(fooClassName3.hasPrefix("Foo"))

        XCTAssertNotNil(barPrefixedClass1)
        XCTAssertNotNil(barPrefixedClass2)
        let barClassName1 = NSStringFromClass(barPrefixedClass1!)
        let barClassName2 = NSStringFromClass(barPrefixedClass2!)
        XCTAssertNotEqual(barClassName1, barClassName2)
        XCTAssertTrue(barClassName1.hasPrefix("Bar"))
        XCTAssertTrue(barClassName2.hasPrefix("Bar"))
    }

    func testConfigurationFailure() {
        var firstClassConfigured = false
        var secondClassConfigured = false

        let firstClass: AnyClass?
        firstClass = Swizzler.createClass(
            with: "SwizzlerTests_",
            superclass: NSObject.self
        ) { _ in
            firstClassConfigured = true
            return false
        }

        let secondClass: AnyClass?
        secondClass = Swizzler.createClass(
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

    // MARK: - Swizzler.addMethods(of: templateClass, to: newClass)

    func testAddingMethodsToDynamicClass() {
        let dynamicClass: AnyClass?
        dynamicClass = Swizzler.createClass(
            with: "SwizzlerAddMethods_",
            superclass: NSObject.self
        ) { newClass in
            do {
                try Swizzler.addMethods(of: DummySubclass.self, to: newClass)
                return true
            } catch {
                XCTAssertNil(error)
                return false
            }
        }

        guard let newClass = dynamicClass else {
            XCTFail("newClass cannot be nil")
            return
        }

        let obj = NSObject()
        XCTAssertNotEqual(obj.description, dummyDescription)

        try! Swizzler.swizzle(obj, with: newClass)

        XCTAssertEqual(obj.description, dummyDescription)
    }

//    + (BOOL)setBlock:(id)blockIMP
//    implementationOf:(SEL)selector
//             inClass:(Class)klass
//               error:(NSError **)error;
}
