/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal enum SwizzlingError: LocalizedError {
    case unknown
    case classIsNotNSObjectSubclass(className: String)
    case methodNotFound(selector: String, className: String)
    case methodWasNotSwizzled(selector: String, className: String)
}

internal class MethodSwizzler {
    static let shared = MethodSwizzler()

    private let queue = DispatchQueue(label: "com.datadoghq.methodSwizzlerQueue", target: DispatchQueue.global(qos: .userInteractive))
    private var implementationCache = [String: IMP]()

    func currentImplementation<TypedIMP>(of selector: Selector, in klass: AnyClass) throws -> TypedIMP {
        try queue.sync {
            let foundMethod = try method(with: selector, in: klass)
            return unsafeBitCast(method_getImplementation(foundMethod), to: TypedIMP.self)
        }
    }

    func swizzle(selector: Selector, in klass: AnyClass, with implementation: IMP) throws {
        try queue.sync {
            if !isKindOfNSObject(klass) {
                throw SwizzlingError.classIsNotNSObjectSubclass(className: NSStringFromClass(klass))
            }
            let foundMethod = try method(with: selector, in: klass)
            let cacheKey = methodIdentifier(foundMethod, in: klass)
            if implementationCache[cacheKey] == nil {
                implementationCache[cacheKey] = method_getImplementation(foundMethod)
            }
            method_setImplementation(foundMethod, implementation)
        }
    }

    func unswizzle(selector: Selector, in klass: AnyClass) throws {
        try queue.sync {
            let foundMethod = try method(with: selector, in: klass)
            let cacheKey = methodIdentifier(foundMethod, in: klass)
            guard let originalImp = implementationCache[cacheKey] else {
                throw SwizzlingError.methodWasNotSwizzled(selector: NSStringFromSelector(selector), className: NSStringFromClass(klass))
            }
            method_setImplementation(foundMethod, originalImp)
            implementationCache[cacheKey] = nil
        }
    }

    private func method(with selector: Selector, in klass: AnyClass) throws -> Method {
        var methodsCount: UInt32 = 0
        guard let methods: UnsafeMutablePointer<Method> = class_copyMethodList(klass, withUnsafeMutablePointer(to: &methodsCount) { $0 }) else {
            throw SwizzlingError.methodNotFound(selector: NSStringFromSelector(selector), className: NSStringFromClass(klass))
        }
        defer {
            free(methods)
        }
        for index in 0..<Int(methodsCount) {
            let method = methods.advanced(by: index).pointee
            if method_getName(method) == selector {
                return method
            }
        }
        throw SwizzlingError.methodNotFound(selector: NSStringFromSelector(selector), className: NSStringFromClass(klass))
    }

    private func methodIdentifier(_ method: Method, in klass: AnyClass) -> String {
        let klassName = NSStringFromClass(klass)
        let methodName = NSStringFromSelector(method_getName(method))
        return "\(klassName)|||\(methodName)"
    }

    private func isKindOfNSObject(_ klass: AnyClass) -> Bool {
        let NSObjectClassName: String = NSStringFromClass(NSObject.self)
        var head: AnyClass? = klass
        while let headClass = head {
            if NSStringFromClass(headClass) == NSObjectClassName {
                return true
            }
            head = class_getSuperclass(head)
        }
        return false
    }
}
