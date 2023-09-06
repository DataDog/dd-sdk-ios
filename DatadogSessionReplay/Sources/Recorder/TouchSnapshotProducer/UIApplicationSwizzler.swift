/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit
import DatadogInternal

// MARK: - Copy & Paste from Datadog SDK

// TODO: RUMM-2756 Share following code with V2's core module when its ready
// Following code was copy & pasted from Datadog SDK (without other modifications than declaring
// it a `final` class for mock convenience). After V2 it should be rather moved to common core module.

internal protocol UIEventHandler: AnyObject {
    func notify_sendEvent(application: UIApplication, event: UIEvent)
}

internal final class UIApplicationSwizzler {
    let sendEvent: SendEvent

    init(handler: UIEventHandler) throws {
        sendEvent = try SendEvent(handler: handler)
    }

    func swizzle() {
        sendEvent.swizzle()
    }

    internal func unswizzle() {
        sendEvent.unswizzle()
    }

    // MARK: - Swizzlings

    /// Swizzles the `UIApplication.sendEvent(_:)`
    class SendEvent: MethodSwizzler <
        @convention(c) (UIApplication, Selector, UIEvent) -> Bool,
        @convention(block) (UIApplication, UIEvent) -> Bool
    > {
        private static let selector = #selector(UIApplication.sendEvent(_:))
        private let method: FoundMethod
        private let handler: UIEventHandler

        init(handler: UIEventHandler) throws {
            self.method = try Self.findMethod(with: Self.selector, in: UIApplication.self)
            self.handler = handler
        }

        func swizzle() {
            typealias Signature = @convention(block) (UIApplication, UIEvent) -> Bool
            swizzle(method) { previousImplementation -> Signature in
                return { [weak handler = self.handler] application, event  in
                    handler?.notify_sendEvent(application: application, event: event)
                    return previousImplementation(application, Self.selector, event)
                }
            }
        }
    }
}

internal class MethodSwizzler<TypedIMP, TypedBlockIMP> {
    struct FoundMethod: Hashable {
        let method: Method
        let klass: AnyClass

        fileprivate init(method: Method, klass: AnyClass) {
            self.method = method
            self.klass = klass
        }

        static func == (lhs: FoundMethod, rhs: FoundMethod) -> Bool {
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

    private var implementationCache: [FoundMethod: IMP] = [:]
    var swizzledMethods: [FoundMethod] {
        return Array(implementationCache.keys)
    }

    static func findMethod(with selector: Selector, in klass: AnyClass) throws -> FoundMethod {
        /// NOTE: RUMM-452 as we never add/remove methods/classes at runtime,
        /// search operation doesn't have to wrapped in sync {...} although it's visible in the interface
        var headKlass: AnyClass? = klass
        while let someKlass = headKlass {
            if let foundMethod = findMethod(with: selector, in: someKlass) {
                return FoundMethod(method: foundMethod, klass: someKlass)
            }
            headKlass = class_getSuperclass(headKlass)
        }
        throw InternalError(description: "\(NSStringFromSelector(selector)) is not found in \(NSStringFromClass(klass))")
    }

    func originalImplementation(of found: FoundMethod) -> TypedIMP {
        return sync {
            let originalImp: IMP = implementationCache[found] ?? method_getImplementation(found.method)
            return unsafeBitCast(originalImp, to: TypedIMP.self)
        }
    }

    func swizzle(
        _ foundMethod: FoundMethod,
        impProvider: (TypedIMP) -> TypedBlockIMP
    ) {
        sync {
            let currentIMP = method_getImplementation(foundMethod.method)
            let current_typedIMP = unsafeBitCast(currentIMP, to: TypedIMP.self)
            let newImpBlock: TypedBlockIMP = impProvider(current_typedIMP)
            let newImp: IMP = imp_implementationWithBlock(newImpBlock)

            set(newIMP: newImp, for: foundMethod)

            #if DD_SDK_COMPILED_FOR_TESTING
            Swizzling.activeSwizzlingNames.append(foundMethod.swizzlingName)
            #endif
        }
    }

    /// Removes swizzling and resets the method to its original implementation.
    internal func unswizzle() {
        for foundMethod in swizzledMethods {
            let originalTypedIMP = originalImplementation(of: foundMethod)
            let originalIMP: IMP = unsafeBitCast(originalTypedIMP, to: IMP.self)
            method_setImplementation(foundMethod.method, originalIMP)

            Swizzling.activeSwizzlingNames.removeAll { $0 == foundMethod.swizzlingName }
        }
    }

    // MARK: - Private methods

    @discardableResult
    private func sync<T>(block: () -> T) -> T {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        return block()
    }

    private static func findMethod(with selector: Selector, in klass: AnyClass) -> Method? {
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

internal extension MethodSwizzler.FoundMethod {
    var swizzlingName: String { "\(klass).\(method_getName(method))" }
}
#endif
