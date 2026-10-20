/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(SwiftUI) && os(iOS)
import Foundation
import Combine
#if compiler(>=6.4) && canImport(Observation)
import Observation
#endif
import DatadogInternal

/// A stable, type-erased source of committed navigation destinations.
///
/// Keep one instance for the lifetime of an independent navigation container.
/// Preparing a transition does not change RUM state. Committing it creates a
/// fresh RUM view occurrence, even when its destination metadata matches an
/// earlier occurrence. Cancelling it leaves the current occurrence unchanged.
@available(iOS 27.0, *)
@MainActor
internal final class RUMNavigationTransitions {
    internal struct Snapshot {
        let generation: UInt64
        let destination: RUMView
    }

    private var nextGeneration: UInt64 = 0
    private var currentSnapshot: Snapshot?
    private var preparedDestinations: [String: RUMView] = [:]
    private var observers: [UUID: (Snapshot) -> Void] = [:]

    #if DD_SDK_COMPILED_FOR_TESTING
    internal var observationCount: Int { observers.count }
    internal var testingBeforeInitialDelivery: (() -> Void)?
    #endif

    internal init() {}

    internal convenience init(currentDestination: RUMView) {
        self.init()
        setInitialDestination(currentDestination)
    }

    /// Publishes the container's initial committed destination exactly once.
    /// This allows a stable source to be created before scene-dependent RUM
    /// metadata is available.
    internal func setInitialDestination(_ destination: RUMView) {
        guard currentSnapshot == nil else {
            return
        }
        let snapshot = Snapshot(
            generation: nextGeneration,
            destination: destination
        )
        currentSnapshot = snapshot
        publish(snapshot)
    }

    /// Records a possible destination without starting a RUM view.
    internal func willNavigate(id: String, destination: RUMView) {
        preparedDestinations[id] = destination
    }

    /// Commits the prepared transition and publishes a fresh occurrence.
    internal func commit(id: String) {
        guard let destination = preparedDestinations.removeValue(forKey: id) else {
            return
        }
        nextGeneration &+= 1
        let snapshot = Snapshot(
            generation: nextGeneration,
            destination: destination
        )
        currentSnapshot = snapshot
        publish(snapshot)
    }

    private func publish(_ snapshot: Snapshot) {
        // A callback may commit again or change subscriptions. Nested commits
        // deliver synchronously; never resume an obsolete outer generation.
        for id in Array(observers.keys) {
            guard currentSnapshot?.generation == snapshot.generation else {
                return
            }
            observers[id]?(snapshot)
        }
    }

    /// Cancels a prepared transition without changing the current occurrence.
    internal func cancel(id: String) {
        preparedDestinations.removeValue(forKey: id)
    }

    @discardableResult
    internal func observe(_ observer: @escaping (Snapshot) -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        if let currentSnapshot {
            #if DD_SDK_COMPILED_FOR_TESTING
            testingBeforeInitialDelivery?()
            #endif
            observer(currentSnapshot)
        }
        return id
    }

    internal func removeObserver(_ id: UUID) {
        observers[id] = nil
    }
}

/// One committed destination from an application-owned navigation state stream.
///
/// Its hashable value is retained only as an in-memory occurrence identity. RUM
/// metadata is derived from the value's type and enum case without serializing
/// associated values or invoking customer descriptions.
@available(iOS 27.0, *)
internal struct RUMNavigationDestination {
    internal enum Kind: String, Hashable {
        case root
        case route
        case presentation
    }

    internal struct Identity: Hashable {
        let kind: Kind
        let value: AnyHashable
        let occurrence: AnyHashable?
    }

    internal let identity: Identity
    internal let value: AnyHashable
    internal let kind: Kind
    internal let automaticKey: String
    internal let attributes: [String: Encodable]

    /// Describes the root currently visible in an independent container.
    internal static func root<Value: Hashable>(
        _ value: Value,
        attributes: [String: Encodable] = [:]
    ) -> Self {
        Self(value: value, kind: .root, attributes: attributes)
    }

    /// Describes the last committed route currently visible in a container.
    internal static func route<Value: Hashable>(
        _ value: Value,
        attributes: [String: Encodable] = [:]
    ) -> Self {
        Self(
            value: value,
            kind: .route,
            attributes: attributes,
            occurrence: nil
        )
    }

    /// Describes a route whose source can distinguish equal-value occurrences.
    ///
    /// The occurrence token is an application navigation identity retained only
    /// in memory. It is not a RUM view UUID and is never serialized. A path depth
    /// or coordinator-owned transition identity is sufficient when equal route
    /// values can occupy multiple positions.
    internal static func route<Value: Hashable, Occurrence: Hashable>(
        _ value: Value,
        occurrence: Occurrence,
        attributes: [String: Encodable] = [:]
    ) -> Self {
        Self(
            value: value,
            kind: .route,
            attributes: attributes,
            occurrence: AnyHashable(occurrence)
        )
    }

    /// Describes the sheet or full-screen cover replacing the underlying route.
    internal static func presentation<Value: Hashable>(
        _ value: Value,
        attributes: [String: Encodable] = [:]
    ) -> Self {
        Self(value: value, kind: .presentation, attributes: attributes)
    }

    private init<Value: Hashable>(
        value: Value,
        kind: Kind,
        attributes: [String: Encodable],
        occurrence: AnyHashable? = nil
    ) {
        let value = AnyHashable(value)
        self.identity = Identity(
            kind: kind,
            value: value,
            occurrence: occurrence
        )
        self.value = value
        self.kind = kind
        self.automaticKey = Self.automaticKey(for: value.base)
        self.attributes = attributes
    }

    private static func automaticKey(for value: Any) -> String {
        if case let .enum(caseName) = ReflectionMirror(reflecting: value).displayStyle,
           !caseName.isEmpty {
            return caseName
        }

        let reflectedType = String(reflecting: type(of: value))
        return reflectedType.split(separator: ".").last.map(String.init)
            ?? reflectedType
    }
}

/// Automatic metadata plus optional sparse overrides for semantic navigation.
///
/// Correct occurrence tracking never requires an override. Overrides only tune
/// business-facing names or paths for exceptional destinations.
@available(iOS 27.0, *)
internal struct RUMNavigationMetadata {
    internal struct Override {
        let name: String
        let path: String?
    }

    internal static let automatic = Self()

    internal var namespace: String?
    internal var overrides: [AnyHashable: Override] = [:]

    internal init() {}

    /// Creates automatic metadata beneath one stable container namespace.
    internal static func automatic(in namespace: String) -> Self {
        var metadata = Self()
        metadata.namespace = namespace
        return metadata
    }

    /// Returns a copy with one optional business-facing metadata override.
    internal func overriding<Value: Hashable>(
        _ value: Value,
        name: String,
        path: String? = nil
    ) -> Self {
        var copy = self
        copy.overrides[AnyHashable(value)] = Override(name: name, path: path)
        return copy
    }

    internal func view(for destination: RUMNavigationDestination) -> RUMView {
        let override = overrides[destination.value]
        var view = RUMView(
            name: override?.name ?? Self.humanized(destination.automaticKey),
            attributes: destination.attributes
        )
        view.path = override?.path ?? automaticPath(for: destination)
        return view
    }

    private func automaticPath(for destination: RUMNavigationDestination) -> String {
        var components: [String] = []
        if let namespace {
            components.append(Self.slug(namespace))
        }
        if destination.kind == .presentation {
            components.append("presentation")
        }

        let key = Self.slug(destination.automaticKey)
        if destination.kind != .root || components.last != key {
            components.append(key)
        }
        return "/" + components.filter { !$0.isEmpty }.joined(separator: "/")
    }

    private static func humanized(_ value: String) -> String {
        var result = ""
        for character in value {
            if character.isUppercase, !result.isEmpty {
                result.append(" ")
            }
            result.append(character == "_" ? " " : character)
        }
        return result.capitalized
    }

    private static func slug(_ value: String) -> String {
        let slug = humanized(value)
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "-"
            }
        return String(slug).split(separator: "-").joined(separator: "-")
    }
}

/// Projects an existing accepted-state stream while its original host remains admitted.
@available(iOS 27.0, *)
@MainActor
internal final class RUMNavigationObservedTransitions {
    let transitions = RUMNavigationTransitions()

    private let acceptsDelivery: @MainActor () -> Bool
    private var currentIdentity: RUMNavigationDestination.Identity?
    private var cancellable: AnyCancellable?
    private var stopped = false
    private var inputGeneration: UInt64 = 0
    #if compiler(>=6.4) && canImport(Observation)
    private var observedCurrentDestination: (@MainActor () -> RUMNavigationDestination)?
    private var observedUpdates: PassthroughSubject<RUMNavigationDestination, Never>?
    private var observedGeneration: UInt64 = 0
    #endif

    init<State, Updates: Publisher>(
        updates: Updates,
        acceptsDelivery: @MainActor @escaping () -> Bool,
        destination: @MainActor @escaping (State) -> RUMNavigationDestination,
        metadata: RUMNavigationMetadata = .automatic
    ) where Updates.Output == State, Updates.Failure == Never {
        self.acceptsDelivery = acceptsDelivery
        guard acceptsDelivery() else {
            stopped = true
            return
        }
        let subscription = updates.sink { [weak self] state in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.receive(state, destination: destination, metadata: metadata)
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.receive(state, destination: destination, metadata: metadata)
                }
            }
        }
        if stopped {
            subscription.cancel()
        } else {
            cancellable = subscription
        }
    }

    #if compiler(>=6.4) && canImport(Observation)
    /// Reads one accepted-state property and rearms synchronously after didSet.
    /// The Publisher projection guard remains the single metadata/commit path.
    convenience init(
        observingCurrentDestination: @MainActor @escaping () -> RUMNavigationDestination,
        acceptsDelivery: @MainActor @escaping () -> Bool,
        metadata: RUMNavigationMetadata = .automatic
    ) {
        let updates = PassthroughSubject<RUMNavigationDestination, Never>()
        self.init(
            updates: updates,
            acceptsDelivery: acceptsDelivery,
            destination: { $0 },
            metadata: metadata
        )
        guard !stopped else {
            return
        }
        observedCurrentDestination = observingCurrentDestination
        observedUpdates = updates
        armCurrentDestinationObservation()
    }

    private func armCurrentDestinationObservation() {
        guard !stopped, let projection = observedCurrentDestination,
              let updates = observedUpdates else {
            return
        }
        observedGeneration &+= 1
        let generation = observedGeneration
        inputGeneration &+= 1
        guard accepts(generation: inputGeneration) else {
            return
        }
        let destination = withObservationTracking(options: [.didSet]) {
            projection()
        } onChange: { [weak self] event in
            guard event.kind == .didSet else {
                return
            }
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.armCurrentDestinationObservation()
                }
            } else {
                // Invalid background mutation remains safe; only the latest
                // accepted state is available when main resumes.
                DispatchQueue.main.async { [weak self] in
                    self?.armCurrentDestinationObservation()
                }
            }
        }
        guard !stopped, observedGeneration == generation else {
            return
        }
        updates.send(destination)
    }
    #endif

    func stop() {
        stopped = true
        inputGeneration &+= 1
        #if compiler(>=6.4) && canImport(Observation)
        observedGeneration &+= 1
        observedCurrentDestination = nil
        observedUpdates = nil
        #endif
        cancellable?.cancel()
        cancellable = nil
        currentIdentity = nil
    }

    private func receive<State>(
        _ state: State,
        destination: @MainActor (State) -> RUMNavigationDestination,
        metadata: RUMNavigationMetadata
    ) {
        guard !stopped else {
            return
        }
        inputGeneration &+= 1
        let generation = inputGeneration
        guard accepts(generation: generation) else {
            return
        }

        let resolved = destination(state)
        guard accepts(generation: generation) else {
            return
        }

        // Projection, application-defined equality and metadata hashing can
        // synchronously emit another accepted input. A newer delivery wins.
        let changed = resolved.identity != currentIdentity
        guard accepts(generation: generation), changed else {
            return
        }
        let view = metadata.view(for: resolved)
        guard accepts(generation: generation) else {
            return
        }

        let previousIdentity = currentIdentity
        let isInitial = previousIdentity == nil
        currentIdentity = resolved.identity
        withExtendedLifetime(previousIdentity) {
            if isInitial {
                transitions.setInitialDestination(view)
            } else {
                let id = UUID().uuidString
                transitions.willNavigate(id: id, destination: view)
                transitions.commit(id: id)
            }
        }
    }

    private func accepts(generation: UInt64) -> Bool {
        guard !stopped, generation == inputGeneration else {
            return false
        }
        let admitted = acceptsDelivery()
        // An obsolete invocation must not stop the newer nested delivery,
        // even when its admission callback returned false.
        guard !stopped, generation == inputGeneration else {
            return false
        }
        guard admitted else {
            stop()
            return false
        }
        return true
    }
}

#endif
