/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Swizzling interface holds references and hierarchy of swizzled
/// methods.
internal enum Swizzling {
    /// List of currently swizzled methods.
    static var methods: [Method] {
        sync { Array($0.keys) }
    }

    /// Describes the current swizzled methods.
    static var description: String {
        methods.map { method_getName($0) }.description
    }

    /// The hierarchy of swizzling per method.
    private static var swizzlings: [Method: MethodSwizzling] = [:]

    /// lock for synchronizing `swizzlings` mutuations.
    private static let lock = NSLock()

    /// Synchronization point to access the swizzling nodes.
    @discardableResult
    fileprivate static func sync<T>(block: (inout [Method: MethodSwizzling]) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block(&swizzlings)
    }
}

/// Linked list of swizzled implementations.
///
/// This object hold the previous (origin) implementation of a
/// method, the override closure reference, and a reference to its
/// parent closure.
private final class MethodSwizzling {
    /// original implementation
    let origin: IMP
    /// type-erased override closure
    let override: OverrideBox
    /// parent swizzling
    let parent: MethodSwizzling?

    init(origin: IMP, override: OverrideBox, parent: MethodSwizzling? = nil) {
        self.origin = origin
        self.override = override
        self.parent = parent
    }
}

/// Reference to type-erased override closure.
private final class OverrideBox {
    let closure: Any
    init(_ closure: Any) {
        self.closure = closure
    }
}

open class MethodSwizzler<Signature, Override> {
    /// List of swizzling managed by this instance.
    private var overrides: [(method: Method, `override`: OverrideBox)] = []

    public init() { }

    /// Swizzle a method with a closure.
    ///
    /// - Parameters:
    ///   - method: The method pointer to swizzle.
    ///   - override: The closure to apply.
    public func swizzle(_ method: Method, override: @escaping (Signature) -> Override) {
        Swizzling.sync { swizzlings in
            let org_imp = method_getImplementation(method)
            let org = unsafeBitCast(org_imp, to: Signature.self)
            let ovr: Override = override(org)
            let ovr_imp: IMP = imp_implementationWithBlock(ovr)

            let override = OverrideBox(override)
            overrides.append((method, override))

            swizzlings[method] = MethodSwizzling(
                origin: org_imp,
                override: override,
                parent: swizzlings[method]
            )

            method_setImplementation(method, ovr_imp)
        }
    }

    /// Removes swizzling and resets the method to its original implementation.
    public func unswizzle() {
        Swizzling.sync { swizzlings in
            while let (method, override) = overrides.popLast() {
                guard let swizzling = swizzlings[method] else {
                    continue
                }

                swizzlings[method] = _unswizzle(
                    method: method,
                    override: override,
                    in: swizzling
                )
            }
        }
    }

    /// Unswizzle a method override.
    ///
    /// If found, the given override will be remove from the hierachy and swizzling will
    /// be re-applied for children to also remove the override from the callstack.
    ///
    /// - Parameters:
    ///   - method: The method to unswizzle.
    ///   - override: The override closure to remove from swizzling.
    ///   - node: The swizzling hierarchy.
    /// - Returns: The new swizzling hierarchy if any.
    private func _unswizzle(method: Method, override: OverrideBox, in swizzling: MethodSwizzling) -> MethodSwizzling? {
        if swizzling.override === override {
            // If found, reset the method implementation
            method_setImplementation(method, swizzling.origin)
            // return the parent to remove the node from the list
            return swizzling.parent
        }

        // depth-first traversal
        let parent = swizzling.parent.flatMap {
            _unswizzle(method: method, override: override, in: $0)
        }

        if let override = swizzling.override.closure as? (Signature) -> Override {
            // Re-apply swizzling for current override
            let org_imp = method_getImplementation(method)
            let org = unsafeBitCast(org_imp, to: Signature.self)
            let ovr: Override = override(org)
            let ovr_imp: IMP = imp_implementationWithBlock(ovr)

            method_setImplementation(method, ovr_imp)
            return MethodSwizzling(
                origin: org_imp,
                override: swizzling.override,
                parent: parent
            )
        }

        // We should never get here as the closure will always
        // satify the type: return the node anyway.
        return swizzling
    }
}

// MARK: - Find Method

public func dd_sel_findMethod(_ sel: Selector, in klass: AnyClass) throws -> Method {
    /// NOTE: RUMM-452 as we never add/remove methods/classes at runtime,
    /// search operation doesn't have to wrapped in sync {...} although it's visible in the interface
    var headKlass: AnyClass? = klass
    while let someKlass = headKlass {
        if let method = sel_findMethod(sel, in: someKlass) {
            return method
        }
        headKlass = class_getSuperclass(headKlass)
    }
    throw InternalError(description: "\(NSStringFromSelector(sel)) is not found in \(NSStringFromClass(klass))")
}

private func sel_findMethod(_ sel: Selector, in klass: AnyClass) -> Method? {
    var methodsCount: UInt32 = 0
    let methodsCountPtr = withUnsafeMutablePointer(to: &methodsCount) { $0 }
    guard let methods: UnsafeMutablePointer<Method> = class_copyMethodList(klass, methodsCountPtr) else {
        return nil
    }

    defer { free(methods) }

    for index in 0..<Int(methodsCount) {
        let method = methods.advanced(by: index).pointee
        if method_getName(method) == sel {
            return method
        }
    }

    return nil
}
