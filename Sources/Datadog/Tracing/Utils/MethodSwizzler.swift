/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

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
    private var _unsafeImplementationCache = [FoundMethod: IMP]()
    private var implementationCache: [FoundMethod: IMP] {
        get { return sync { return _unsafeImplementationCache } }
        set { sync { _unsafeImplementationCache = newValue } }
    }

    var swizzledCount: Int { return implementationCache.count }

    func findMethodRecursively(with selector: Selector, in klass: AnyClass) -> FoundMethod? {
        return sync {
            var headKlass: AnyClass? = klass
            while let someKlass = headKlass {
                if let foundMethod = findMethod(with: selector, in: someKlass) {
                    return FoundMethod(method: foundMethod, klass: someKlass)
                }
                headKlass = class_getSuperclass(headKlass)
            }
            return nil
        }
    }

    func currentImplementation<TypedIMP>(of found: FoundMethod) -> TypedIMP {
        return sync {
            return unsafeBitCast(method_getImplementation(found.method), to: TypedIMP.self)
        }
    }

    func originalImplementation<TypedIMP>(of found: FoundMethod) -> TypedIMP {
        return sync {
            let originalImp: IMP = implementationCache[found] ?? method_getImplementation(found.method)
            return unsafeBitCast(originalImp, to: TypedIMP.self)
        }
    }

    @discardableResult
    func swizzleIfNonSwizzled(
        foundMethod: FoundMethod,
        with implementation: @autoclosure () -> IMP
    ) -> Bool {
        sync {
            if implementationCache[foundMethod] != nil {
                return false
            }
            set(newIMP: implementation(), for: foundMethod)
            return true
        }
    }

    func set(newIMP: IMP, for found: FoundMethod) {
        sync {
            if implementationCache[found] == nil {
                implementationCache[found] = method_getImplementation(found.method)
            }
            method_setImplementation(found.method, newIMP)
        }
    }

    // MARK: - Unsafe methods

    @discardableResult
    func unsafe_unswizzle(_ found: FoundMethod) -> Bool {
        return sync {
            guard let cachedImp = implementationCache[found] else {
                return false
            }
            set(newIMP: cachedImp, for: found)
            implementationCache[found] = nil
            return true
        }
    }

    func unsafe_unswizzleALL() {
        return sync {
            let cachedMethods: [FoundMethod] = Array(implementationCache.keys)
            for foundMethod in cachedMethods {
                unsafe_unswizzle(foundMethod)
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
}
