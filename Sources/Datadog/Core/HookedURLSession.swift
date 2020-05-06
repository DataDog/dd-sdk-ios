/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

// swiftlint:disable multiline_arguments_brackets
// swiftlint:disable vertical_whitespace_opening_braces

import Foundation
import ObjectiveC.runtime

// TODO: RUMM-300 Find a way to inject blocks/custom code to hooked methods

@objc(HookedURLSession)
private final class HookedURLSession: URLSession {

    @objc(dataTaskWithURL:)
    override func dataTask(with url: URL) -> URLSessionDataTask {
        print("BOOM")
        return dataTask(with: URLRequest(url: url))
    }

    func swiftFunctionNotToBeAdded() { }
}

@objc(HookedURLSessionTask)
private final class HookedURLSessionTask: URLSessionTask { }

internal final class Swizzler {

    enum ObjCRuntimeError: Error {
        case internalError
        case classCouldNotAllocated
    }

    static func isaSwizzle(_ object: AnyObject) throws {
        let templateClassName: String
        if object.isKind(of: URLSession.self) {
            templateClassName = NSStringFromClass(HookedURLSession.self)
        } else if object.isKind(of: URLSessionTask.self) {
            templateClassName = NSStringFromClass(HookedURLSessionTask.self)
        } else {
            // TODO: RUMM-300 Log this case
            return
        }

        guard let templateClass = objc_getClass(templateClassName) as? AnyClass else {
            // Check if template classes (HookedURLSession/Task) match
            throw ObjCRuntimeError.internalError
        }
        let dynamicClass: AnyClass = try dynamicSubclass(for: object, templateClass: templateClass)
        object_setClass(object, dynamicClass)
    }

    // MARK: - Private

    private static func dynamicSubclass(for object: AnyObject, templateClass: AnyClass) throws -> AnyClass {
        let dynamicClassPrefix = "_Datadog"
        let superclass: AnyClass? = object_getClass(object)
        let superclassName = class_getName(superclass)
        // TODO: RUMM-300 Test %s with right-to-left languages
        let dynamicClassName = String(format: "\(dynamicClassPrefix)%s", superclassName)
        if let existingClass = objc_lookUpClass(dynamicClassName) {
            return existingClass
        }

        guard let newClass = objc_allocateClassPair(superclass, dynamicClassName, 0) else {
                throw ObjCRuntimeError.classCouldNotAllocated
        }
        addInstanceMethods(of: templateClass, to: newClass)
        objc_registerClassPair(newClass)
        return newClass
    }

    private static func addInstanceMethods(of sourceClass: AnyClass, to targetClass: AnyClass) {
        let sourceMethodsCountPtr = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        defer { sourceMethodsCountPtr.deallocate() }

        let copyMethodList: UnsafeMutablePointer<Method>? = class_copyMethodList(sourceClass,
                                                                                 sourceMethodsCountPtr)
        typealias Stride = UnsafeMutablePointer<Method>.Stride
        let sourceMethodsCount = Stride(clamping: sourceMethodsCountPtr.pointee)
        guard let sourceMethodsList = copyMethodList, sourceMethodsCount > 0 else {
                return // No instance methods to add
        }

        for index in 0..<sourceMethodsCount {
            let method: Method = sourceMethodsList.advanced(by: index).pointee
            add(method: method, to: targetClass)
        }
    }

    private static func add(method: Method, to klass: AnyClass) {
        let selector = method_getName(method)
        let imp = method_getImplementation(method)
        let types = method_getTypeEncoding(method)
        let success = class_addMethod(klass, selector, imp, types)
        if !success {
            // TODO: RUMM-300 Log this case
            return
        }
    }
}

// swiftlint:enable multiline_arguments_brackets
// swiftlint:enable vertical_whitespace_opening_braces
