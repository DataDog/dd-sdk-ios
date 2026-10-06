/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

@_spi(Internal)
import DatadogInternal

/// A type providing core context and writer for writing span events.
internal protocol SpanWriteContext {
    /// Requests core context and writer for writing span events.
    /// - Parameter block: The block to execute; it is called on the core's context queue.
    func spanWriteContext(_ block: @escaping (DatadogContext, Writer) -> Void)
}

/// A `SpanWriteContext` that captures core context at the moment of initialization and provides it
/// later when the actual span event is constructed.
///
/// It ensures that spans are constructed with the context valid at the moment of span creation (_start span_)
/// instead of completion (_finish span_). This enables the proper linking of attributes from other products, like
/// associating started span with the current RUM information.
internal final class LazySpanWriteContext: SpanWriteContext {
    /// Trace feature scope.
    let featureScope: FeatureScope

    /// The core context valid at the moment of creating `LazySpanWriteContext`.
    /// It doesn't require synchronization as it is accessed only from the core context queue.
    private var context: DatadogContext?
    /// `nil` preserves the context captured by this writer. A present optional replaces only RUM context.
    private let rumContext: RUMCoreContext??

    init(featureScope: FeatureScope, rumContext: RUMCoreContext?? = nil) {
        self.featureScope = featureScope
        self.rumContext = rumContext

        // Capture the core context valid at the moment of initialization:
        featureScope.context { [weak self] context in
            self?.context = context
        }
    }

    func spanWriteContext(_ block: @escaping (DatadogContext, Writer) -> Void) {
        // Ignore the current context and use the one captured at initialization:
        featureScope.eventWriteContext { _, writer in
            guard var context = self.context else {
                return // unexpected
            }
            if let rumContext = self.rumContext {
                context.set(additionalContext: rumContext)
            }
            block(context, writer)
        }
    }
}

/// Resolves the original captured action at serialization on the Core queue.
internal final class CapturedRUMSpanWriteContext: SpanWriteContext {
    enum SessionOwnership {
        case captured
        case request(String?)
    }

    private let original: SpanWriteContext
    private let owner: RUMContextHandoff.Owner
    private let value: RUMContextHandoff.CurrentValue
    private let sessionOwnership: SessionOwnership

    init(original: SpanWriteContext, owner: RUMContextHandoff.Owner, value: RUMContextHandoff.CurrentValue, sessionOwnership: SessionOwnership) {
        self.original = original
        self.owner = owner
        self.value = value
        self.sessionOwnership = sessionOwnership
    }

    func spanWriteContext(_ block: @escaping (DatadogContext, Writer) -> Void) {
        original.spanWriteContext { context, writer in
            var context = context
            var rumContext = self.value.resolvedRUMContext(for: self.owner)
            if case let .request(sessionID) = self.sessionOwnership,
               rumContext?.sessionID != sessionID {
                rumContext = nil
            }
            context.set(additionalContext: rumContext)
            block(context, writer)
        }
    }
}
