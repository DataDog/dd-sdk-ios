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
    /// A `MethodOverride` associates an override reference to a method
    /// of the Objective-C runtime.
    private typealias MethodOverride = (method: Method, `override`: OverrideBox)

    /// List of overrides managed by this instance.
    private var overrides: [MethodOverride] = []

    public init() { }

    /// Swizzle a method with a closure.
    ///
    /// - Parameters:
    ///   - method: The method pointer to swizzle.
    ///   - override: The closure to apply.
    ///
    /// - Complexity: O(1) on average, over many calls to `swizzle(_:,override:)` on the
    ///   same array. When a swizzler needs to reallocate storage before swizzling, swizzling is O(*n*),
    ///   where *n* is the number of method swizzling managed by this instance.
    public func swizzle(_ method: Method, override: @escaping (Signature) -> Override) {
        Swizzling.sync { swizzlings in
            let origin = method_override(method, override)
            let override = OverrideBox(override)

            swizzlings[method] = MethodSwizzling(
                origin: origin,
                override: override,
                parent: swizzlings[method]
            )

            overrides.append((method, override))
        }
    }

    /// Removes swizzling and resets the method to its previous implementation.
    ///
    /// This method will remove all swizzles that have been created by the instance
    /// only. Other overrides will stay in the callstack.
    /// 
    /// - Complexity: O(*n*), where *n* is the number of the swizzle per method.
    public func unswizzle() {
        Swizzling.sync { swizzlings in
            while let (method, override) = overrides.popLast() {
                guard let swizzling = swizzlings[method] else {
                    continue
                }

                swizzlings[method] = _unswizzle(
                    method: method,
                    override: override,
                    swizzling: swizzling
                )
            }
        }
    }

    /// Unswizzle a method override.
    ///
    /// If found, the given override will be remove from the hierarchy and swizzling will
    /// be re-applied for children to also remove the override from the callstack.
    ///
    /// - Parameters:
    ///   - method: The method to unswizzle.
    ///   - override: The override closure to remove from swizzling.
    ///   - swizzling: The swizzling list.
    /// - Returns: The new swizzling hierarchy if any.
    private func _unswizzle(method: Method, override: OverrideBox, swizzling: MethodSwizzling) -> MethodSwizzling? {
        // reset the method to its previous implementation
        method_setImplementation(method, swizzling.origin)
        // if override is found, stop the recursion and remove the node
        // from the list by returning the parent
        if swizzling.override === override {
            return swizzling.parent
        }
        // if override is not found, go to parent (depth-first traversal)
        let parent = swizzling.parent.flatMap {
            _unswizzle(method: method, override: override, swizzling: $0)
        }
        // at this point, parents have been processed and we can re-apply
        // swizzling override
        guard let override = swizzling.override.closure as? (Signature) -> Override else {
            // we should never get here as the closure will always
            // satisfy the type: remove the node by returning its
            // parent
            return swizzling.parent
        }
        // re-apply swizzling for current override
        return MethodSwizzling(
            origin: method_override(method, override),
            override: swizzling.override,
            parent: parent
        )
    }

    /// Overrides the implementation of a method.
    ///
    /// - Parameters:
    ///   - method: The methods to override.
    ///   - override: The overriding closure.
    /// - Returns: The previous implementation of the method.
    private func method_override(_ method: Method, _ override: @escaping (Signature) -> Override) -> IMP {
        let org_imp = method_getImplementation(method)
        let org = unsafeBitCast(org_imp, to: Signature.self)
        let ovr: Override = override(org)
        let ovr_imp: IMP = imp_implementationWithBlock(ovr)
        return method_setImplementation(method, ovr_imp)
    }
}

extension MethodSwizzler: CustomDebugStringConvertible {
    public var debugDescription: String {
        """
        The MethodSwizzler holds swizzling for:
        \(overrides.map { method_getName($0.method) }.description)
        """
    }
}

// MARK: - Find Method

public func dd_class_getInstanceMethod(_ cls: AnyClass, _ name: Selector) throws -> Method {
    guard let method = class_getInstanceMethod(cls, name) else {
        throw InternalError(description: "\(NSStringFromSelector(name)) is not found in \(NSStringFromClass(cls))")
    }

    return method
}
