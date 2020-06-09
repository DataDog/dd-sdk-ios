/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal enum SwizzlingError: LocalizedError, Equatable {
    case methodNotFound(selector: String, className: String)

    var errorDescription: String? {
        switch self {
        case .methodNotFound(let selector, let className):
            return "\(selector) is not found in \(className)"
        }
    }
}

internal class MethodSwizzler {
    struct FoundMethod: Hashable {
        let method: Method
        let klass: AnyClass

        fileprivate init(method: Method, klass: AnyClass) {
            self.method = method
            self.klass = klass
        }

        static func == (lhs: MethodSwizzler.FoundMethod, rhs: MethodSwizzler.FoundMethod) -> Bool {
            let methodParity = (lhs.method == rhs.method)
            let classParity = (NSStringFromClass(lhs.klass) == NSStringFromClass(rhs.klass))
            return methodParity && classParity
        }

        func hash(into hasher: inout Hasher) {
            let methodName = NSStringFromSelector(method_getName(method))
            let klassName = NSStringFromClass(klass)
            let identifier = "\(methodName)|||\(klassName)"
            hasher.combine(identifier)
        }
    }

    static let shared = MethodSwizzler()
    private init() { }
    private var implementationCache = [FoundMethod: IMP]()

    func findMethod(with selector: Selector, in klass: AnyClass) throws -> FoundMethod {
        /// NOTE: RUMM-452 as we never add/remove methods/classes at runtime,
        /// search operation doesn't have to wrapped in sync {...} although it's visible in the interface
        var headKlass: AnyClass? = klass
        while let someKlass = headKlass {
            if let foundMethod = findMethod(with: selector, in: someKlass) {
                return FoundMethod(method: foundMethod, klass: someKlass)
            }
            headKlass = class_getSuperclass(headKlass)
        }
        throw SwizzlingError.methodNotFound(selector: NSStringFromSelector(selector), className: NSStringFromClass(klass))
    }

    func originalImplementation<TypedIMP>(of found: FoundMethod) -> TypedIMP {
        return sync {
            let originalImp: IMP = implementationCache[found] ?? method_getImplementation(found.method)
            return unsafeBitCast(originalImp, to: TypedIMP.self)
        }
    }

    @discardableResult
    func swizzle<TypedCurrentIMP, TypedNewIMPBlock>(
        _ foundMethod: FoundMethod,
        impSignature: TypedCurrentIMP.Type,
        impProvider: (TypedCurrentIMP) -> TypedNewIMPBlock,
        onlyIfNonSwizzled: Bool = false
    ) -> Bool {
        sync {
            if onlyIfNonSwizzled &&
                implementationCache[foundMethod] != nil {
                return false
            }
            let currentIMP = method_getImplementation(foundMethod.method)
            let current_typedIMP = unsafeBitCast(currentIMP, to: impSignature)
            let newImpBlock: TypedNewIMPBlock = impProvider(current_typedIMP)
            let newImp: IMP = imp_implementationWithBlock(newImpBlock)

            set(newIMP: newImp, for: foundMethod)
            return true
        }
    }

    // MARK: - Unsafe methods

    func unsafe_unswizzleALL() {
        return sync {
            let cachedMethods: [FoundMethod] = Array(implementationCache.keys)
            for foundMethod in cachedMethods {
                if let cachedImp = implementationCache[foundMethod] {
                    set(newIMP: cachedImp, for: foundMethod)
                    implementationCache[foundMethod] = nil
                }
            }
        }
    }

    // MARK: - Private methods

    @discardableResult
    private func sync<T>(block: () -> T) -> T {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        return block()
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

    private func set(newIMP: IMP, for found: FoundMethod) {
        if implementationCache[found] == nil {
            implementationCache[found] = method_getImplementation(found.method)
        }
        method_setImplementation(found.method, newIMP)
    }
}
