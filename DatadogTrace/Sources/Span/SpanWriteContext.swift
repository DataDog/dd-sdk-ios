/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

/// A type providing core context and writer for writing span events.
internal protocol SpanWriteContext {
    /// Requests core context and writer for writing span events.
    /// - Parameter block: The block to execute; it is called on the core's context queue.
    func spanWriteContext(_ block: @escaping (DatadogContext, Writer) -> Void)
}

/// Controls the RUM context attached to a span without changing its other context.
internal enum RUMContextOverride {
    /// Keep the RUM context captured when the span writer was created.
    case preserve
    /// Explicitly leave the span without RUM context.
    case remove
    /// Use the RUM context captured when the request started.
    case replace(RUMCoreContext)
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
    /// The request-time override, or `.preserve` for spans that use the writer's captured context.
    private let rumContextOverride: RUMContextOverride

    init(featureScope: FeatureScope, rumContextOverride: RUMContextOverride = .preserve) {
        self.featureScope = featureScope
        self.rumContextOverride = rumContextOverride

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
            switch self.rumContextOverride {
            case .preserve:
                break
            case .remove:
                context.removeContext(ofType: RUMCoreContext.self)
            case .replace(let rumContext):
                context.set(additionalContext: rumContext)
            }
            block(context, writer)
        }
    }
}
