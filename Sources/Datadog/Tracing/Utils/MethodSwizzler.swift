/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal enum SwizzlingError: LocalizedError, Equatable {
    case methodNotFound(selector: String, className: String)
    case methodIsAlreadySwizzled(selector: String, targetClassName: String, swizzledClassName: String)
    case methodWasNotSwizzled(selector: String, className: String)

    var errorDescription: String? {
        switch self {
        case .methodNotFound(let selector, let className):
            return "\(selector) is not found in \(className)"
        case .methodIsAlreadySwizzled(let selector, let targetClassName, let swizzledClassName):
            return "\(selector) of \(targetClassName) is already swizzled in \(swizzledClassName)"
        case .methodWasNotSwizzled(let selector, let className):
            return "\(selector) in \(className) was not swizzled, thus cannot be unswizzled"
        }
    }
}

internal class MethodSwizzler {
    private typealias FoundMethod = (method: Method, klass: AnyClass)

    static let shared = MethodSwizzler()
    private init() { }
    private var implementationCache = [String: IMP]()

    func currentImplementation<TypedIMP>(of selector: Selector, in klass: AnyClass) throws -> TypedIMP {
        return try sync {
            let found = try findMethodRecursively(with: selector, in: klass)
            return unsafeBitCast(method_getImplementation(found.method), to: TypedIMP.self)
        }
    }

    func originalImplementation<TypedIMP>(of selector: Selector, in klass: AnyClass) throws -> TypedIMP {
        return try sync {
            let found = try findMethodRecursively(with: selector, in: klass)
            let cacheKey = methodIdentifier(for: found)
            let originalImp: IMP = implementationCache[cacheKey] ?? method_getImplementation(found.method)
            return unsafeBitCast(originalImp, to: TypedIMP.self)
        }
    }

    func swizzle(selector: Selector, in klass: AnyClass, with implementation: IMP) throws {
        try sync {
            assert(isKindOfNSObject(klass), "\(klass) is not NSObject subclass: swizzling may not work!")
            let found = try findMethodRecursively(with: selector, in: klass)
            set(newIMP: implementation, for: found)
        }
    }

    func swizzleIfNonSwizzled(
        selector: Selector,
        in klass: AnyClass,
        with implementation: @autoclosure () throws -> IMP
    ) throws {
        try sync {
            let found = try findMethodRecursively(with: selector, in: klass)
            let methodID = methodIdentifier(for: found)
            if implementationCache[methodID] != nil {
                throw SwizzlingError.methodIsAlreadySwizzled(
                    selector: NSStringFromSelector(selector),
                    targetClassName: NSStringFromClass(klass),
                    swizzledClassName: NSStringFromClass(found.klass)
                )
            }
            assert(isKindOfNSObject(found.klass), "\(klass) is not NSObject subclass: swizzling may not work!")
            set(newIMP: try implementation(), for: found)
        }
    }

    func unswizzle(selector: Selector, in klass: AnyClass) throws {
        return try sync {
            let found = try findMethodRecursively(with: selector, in: klass)
            let cacheKey = methodIdentifier(for: found)
            guard let originalImp = implementationCache[cacheKey] else {
                throw SwizzlingError.methodWasNotSwizzled(selector: NSStringFromSelector(selector), className: NSStringFromClass(klass))
            }
            method_setImplementation(found.method, originalImp)
            implementationCache[cacheKey] = nil
        }
    }

    // MARK: - Private methods

    private func sync<T>(block: () throws -> T) throws -> T {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        return try block()
    }

    private func set(newIMP: IMP, for found: FoundMethod) {
        let cacheKey = methodIdentifier(for: found)
        if implementationCache[cacheKey] == nil {
            implementationCache[cacheKey] = method_getImplementation(found.method)
        }
        method_setImplementation(found.method, newIMP)
    }

    private func findMethodRecursively(with selector: Selector, in klass: AnyClass) throws -> FoundMethod {
        var headKlass: AnyClass? = klass
        while let someKlass = headKlass {
            if let foundMethod = findMethod(with: selector, in: someKlass) {
                return (method: foundMethod, klass: someKlass)
            }
            headKlass = class_getSuperclass(headKlass)
        }
        throw SwizzlingError.methodNotFound(selector: NSStringFromSelector(selector), className: NSStringFromClass(klass))
    }

    private func findMethod(with selector: Selector, in klass: AnyClass) -> Method? {
        var methodsCount: UInt32 = 0
        let methodsCountPtr = withUnsafeMutablePointer(to: &methodsCount) { $0 }
        guard let methods: UnsafeMutablePointer<Method> = class_copyMethodList(klass, methodsCountPtr) else {
            return nil
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
        return nil
    }

    private static let separator = "|||"
    private func methodIdentifier(for found: FoundMethod) -> String {
        let klassName = NSStringFromClass(found.klass)
        let methodName = NSStringFromSelector(method_getName(found.method))
        return "\(klassName)\(Self.separator)\(methodName)"
    }

    private func classSelectorPair(from methodIdentifier: String) -> (klass: AnyClass, selector: Selector)? {
        let classSelectorPair = methodIdentifier.components(separatedBy: Self.separator)
        if classSelectorPair.count == 2,
            let klass = NSClassFromString(classSelectorPair[0]) {
            let selector = NSSelectorFromString(classSelectorPair[1])
            return (klass: klass, selector: selector)
        } else {
            return nil
        }
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

    // MARK: - DEBUG only

    // TODO: RUMM-452 only for unit tests?
    #if DEBUG
    func unswizzleALL() {
        let cachedKeys: [String] = Array(implementationCache.keys)
        for key in cachedKeys {
            if let classSelPair = classSelectorPair(from: key) {
                try? unswizzle(selector: classSelPair.selector, in: classSelPair.klass)
            }
        }
    }
    #endif
}
