/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// The `Reflector` container provides convenient methods to
/// reflect an instance using the ``ReflectionMirror`` mirroring
/// implementation and ceate ``Reflection`` objects.
///
/// The `Reflector` is capabale of reporting telemetry error while
/// reflecting descendants and procide partial results on Sequence.
internal struct Reflector {
    /// Escalated error during reflection.
    enum Error: Swift.Error {
        struct Context {
            let subjectType: Any.Type
            let paths: [ReflectionMirror.Path]
        }
        case notFound(Context)
        case typeMismatch(Context, expect: Any.Type, got: Any.Type)
    }

    /// A `Lazy` reflection allows reflecting the subject at a later time.
    struct Lazy<T> where T: Reflection {
        private let mirror: ReflectionMirror
    }

    private let mirror: ReflectionMirror
    private let telemetry: Telemetry

    /// Accessor of the mirror's display style.
    var displayStyle: ReflectionMirror.DisplayStyle {
        mirror.displayStyle
    }

    /// Creates a reflector.
    ///
    /// - Parameters:
    ///   - mirror: The reflection mirror instance.
    ///   - telemetry: The telemetry to report reflection errors.
    private init(
        mirror: ReflectionMirror,
        telemetry: Telemetry = NOPTelemetry()
    ) {
        self.mirror = mirror
        self.telemetry = telemetry
    }

    /// Reflects a subject.
    ///
    /// - Parameters:
    ///   - subject: The subject instance to reflect.
    ///   - telemetry: The telemetry to report reflection errors.
    init(
        subject: Any?,
        telemetry: Telemetry
    ) {
        self.init(
            mirror: ReflectionMirror(reflecting: subject as Any),
            telemetry: telemetry
        )
    }

    /// Get a descendant at a given path.
    ///
    /// - Parameter paths: The path to the descendant..
    /// - Returns: The descendant instance if it exist at the provided path.
    func descendant(_ paths: [ReflectionMirror.Path]) -> Any? {
        mirror.descendant(paths)
    }

    /// Access a descendant of `Any` type by path.
    ///
    /// This method provide direct access to the mirror.
    ///
    /// - Parameters:
    ///   - first: The first path element.
    ///   - rest: The rest of the path elements.
    /// - Returns: The descendant instance if it exist at the provided path.
    func descendantIfPresent(_ first: ReflectionMirror.Path, _ rest: ReflectionMirror.Path...) -> Any? {
        descendant([first] + rest)
    }

    /// Reports a reflection error.
    ///
    /// - Parameter error: The error to report.
    func report(_ error: Swift.Error) {
        telemetry.error(error)
    }
}

/// A `Reflection` object can intialize itself by reflecting an instance
/// through a ``Reflector``.
///
/// Similar to `Decodable`, a `Reflection` can access mirroring descendant
/// by path based in the `displayStyle`.
internal protocol Reflection {
    /// Creates a new instance by reflection from the given reflector.
    ///
    /// This initializer throws an error if reading from the reflector fails, or
    /// if the data read is corrupted or otherwise invalid.
    ///
    /// - Parameter reflector: The reflector to read descendant from.
    init(from reflector: Reflector) throws
}

// swiftlint:disable function_default_parameter_at_end
extension Reflector {
    /// Access a descendant of `Any` type by path.
    ///
    /// This method provide direct access to the mirror.
    ///
    /// - Parameters:
    ///   - first: The first path element.
    ///   - rest: The rest of the path elements.
    /// - Returns: The descendant instance if it exist at the provided path.
    func descendantIfPresent<T>(type: T.Type = T.self, _ first: ReflectionMirror.Path, _ rest: ReflectionMirror.Path...) -> T? {
        descendant([first] + rest) as? T
    }

    /// Access a descendant of specified type by path.
    ///
    /// - Parameters:
    ///   - type: The expected descendant type.
    ///   - first: The first path element.
    ///   - rest: The rest of the path elements.
    /// - Returns: The descendant instance if it exist at the provided path.
    /// - Throws: `Reflector.Error.notFound` or `Reflector.Error.typeMismatch`
    func descendant<T>(type: T.Type = T.self, _ first: ReflectionMirror.Path, _ rest: ReflectionMirror.Path...) throws -> T {
        try descendant([first] + rest)
    }

    private func descendant<T>(type: T.Type = T.self, _ paths: [ReflectionMirror.Path]) throws -> T {
        guard let value = descendant(paths) else {
            throw Error.notFound(.init(subjectType: mirror.subjectType, paths: paths))
        }

        guard let value = value as? T else {
            throw Error.typeMismatch(
                .init(subjectType: mirror.subjectType, paths: paths),
                expect: type,
                got: Swift.type(of: value)
            )
        }

        return value
    }
}

extension Reflector {
    /// Reflect a subjec to a specified type.
    ///
    /// - Parameters:
    ///   - type: The type to reflect to.
    ///   - subject: The subject instance to reflect.
    /// - Returns: The reflection instance.
    func reflect<T>(type: T.Type = T.self, _ subject: Any?) throws -> T where T: Reflection {
        let reflector = Reflector(subject: subject, telemetry: telemetry)
        return try T(from: reflector)
    }

    /// Reflect an optional descendant to the specified type by path.
    ///
    /// - Parameters:
    ///   - type: The expected descendant type.
    ///   - first: The first path element.
    ///   - rest: The rest of the path elements.
    /// - Returns: The descendant instance if it exist at the provided path.
    func descendantIfPresent<T>(type: T.Type = T.self, _ first: ReflectionMirror.Path, _ rest: ReflectionMirror.Path...) -> T? where T: Reflection {
        do {
            return try descendant(type: type, [first] + rest)
        } catch Error.notFound {
            return nil
        } catch {
            report(error)
            return nil
        }
    }

    /// Reflect a descendant to the specified Element type by path.
    ///
    /// - Parameters:
    ///   - type: The expected descendant type.
    ///   - first: The first path element.
    ///   - rest: The rest of the path elements.
    /// - Returns: The descendant instance if it exist at the provided path.
    /// - Throws: `Reflector.Error` or any other error from the `Reflection` type.
    func descendant<T>(type: T.Type = T.self, _ first: ReflectionMirror.Path, _ rest: ReflectionMirror.Path...) throws -> T where T: Reflection {
        try descendant(type: type, [first] + rest)
    }

    /// Reflect a Collection descendant of the specified type by path.
    ///
    /// - Parameters:
    ///   - type: The expected element type.
    ///   - first: The first path element.
    ///   - rest: The rest of the path elements.
    /// - Returns: The descendant instance if it exist at the provided path.
    /// - Throws: `Reflector.Error` or any other error from the `Reflection` type.
    func descendant<Element>(_ first: ReflectionMirror.Path, _ rest: ReflectionMirror.Path...) throws -> [Element] where Element: Reflection {
        guard let subject = descendant([first] + rest) as? [Any] else {
            throw Error.typeMismatch(
                .init(subjectType: mirror.subjectType, paths: [first] + rest),
                expect: [Any].self,
                got: mirror.subjectType
            )
        }

        return subject.compactMap {
            do {
                return try reflect($0)
            } catch {
                report(error)
                return nil
            }
        }
    }

    /// Reflect a Disctionary descendant to the specified Key/Value types by path.
    ///
    /// - Parameters:
    ///   - type: The expected element type.
    ///   - first: The first path element.
    ///   - rest: The rest of the path elements.
    /// - Returns: The descendant instance if it exist at the provided path.
    /// - Throws: `Reflector.Error` or any other error from the `Reflection` type.
    func descendant<Key, Value>(_ first: ReflectionMirror.Path, _ rest: ReflectionMirror.Path...) throws -> [Key: Value] where Key: Hashable, Value: Reflection {
        guard let subject = descendant([first] + rest) as? [Key: Any] else {
            throw Error.typeMismatch(
                .init(subjectType: mirror.subjectType, paths: [first] + rest),
                expect: [Key: Any].self,
                got: mirror.subjectType
            )
        }

        return subject.reduce(into: [:]) { result, element in
            do {
                try result[element.key] = reflect(element.value)
            } catch {
                report(error)
            }
        }
    }

    /// Reflect a Disctionary descendant to the specified Key/Value types by path.
    ///
    /// - Parameters:
    ///   - type: The expected element type.
    ///   - first: The first path element.
    ///   - rest: The rest of the path elements.
    /// - Returns: The descendant instance if it exist at the provided path.
    /// - Throws: `Reflector.Error` or any other error from the `Reflection` type.
    func descendant<Key, Value>(_ first: ReflectionMirror.Path, _ rest: ReflectionMirror.Path...) throws -> [Key: Value] where Key: Reflection, Key: Hashable, Value: Reflection {
        guard let subject = descendant([first] + rest) as? [AnyHashable: Any] else {
            throw Error.typeMismatch(
                .init(subjectType: mirror.subjectType, paths: [first] + rest),
                expect: [AnyHashable: Any].self,
                got: mirror.subjectType
            )
        }

        return subject.reduce(into: [:]) { result, element in
            do {
                try result[reflect(element.key.base)] = reflect(element.value)
            } catch {
                report(error)
            }
        }
    }

    private func descendant<T>(type: T.Type = T.self, _ paths: [ReflectionMirror.Path]) throws -> T where T: Reflection {
        guard let value = descendant(paths) else {
            throw Error.notFound(.init(subjectType: mirror.subjectType, paths: paths))
        }

        let reflector = Reflector(
            subject: value,
            telemetry: telemetry
        )

        return try T(from: reflector)
    }
}
// swiftlint:enable function_default_parameter_at_end

extension Reflection {
    typealias Lazy = Reflector.Lazy<Self>
}

extension Reflector.Lazy: Reflection {
    init(from reflector: Reflector) throws {
        self.mirror = reflector.mirror
    }
    
    /// Relect to the type `T` and report error to telemetry.
    ///
    /// - Parameter telemetry: The telemetry instance.
    /// - Returns: The relection of type `T`.
    func reflect(telemetry: Telemetry) throws -> T {
        let reflector = Reflector(mirror: mirror, telemetry: telemetry)
        return try T(from: reflector)
    }
}
