/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
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

    init(featureScope: FeatureScope) {
        self.featureScope = featureScope

        // Capture the core context valid at the moment of initialization:
        featureScope.context { [weak self] context in
            self?.context = context
        }
    }

    /// Captures the current core context while replacing its RUM component with
    /// the one observed when asynchronous work actually started.
    init(
        featureScope: FeatureScope,
        rumContext: RUMCoreContext?,
        hasPendingUserAction: Bool = false,
        excludedUserActionID: String? = nil
    ) {
        self.featureScope = featureScope

        featureScope.context { [weak self] context in
            var context = context
            let resolvedRUMContext = hasPendingUserAction
                ? mergeAcceptedUIEventAction(
                    into: rumContext,
                    from: context.additionalContext(ofType: RUMCoreContext.self),
                    excluding: excludedUserActionID
                )
                : rumContext
            if let resolvedRUMContext {
                context.set(additionalContext: resolvedRUMContext)
            } else {
                context.removeContext(ofType: RUMCoreContext.self)
            }
            self?.context = context
        }
    }

    func spanWriteContext(_ block: @escaping (DatadogContext, Writer) -> Void) {
        // Ignore the current context and use the one captured at initialization:
        featureScope.eventWriteContext { _, writer in
            guard let context = self.context else {
                return // unexpected
            }
            block(context, writer)
        }
    }
}

private func mergeAcceptedUIEventAction(
    into captured: RUMCoreContext?,
    from current: RUMCoreContext?,
    excluding excludedUserActionID: String?
) -> RUMCoreContext? {
    guard let captured,
          let current,
          let currentActionID = current.userActionID,
          UUID(uuidString: currentActionID) != nil,
          currentActionID != excludedUserActionID else {
        return captured
    }

    guard captured.applicationID == current.applicationID,
          captured.sessionID == current.sessionID,
          captured.viewID == current.viewID else {
        return captured
    }
    return RUMCoreContext(
        applicationID: captured.applicationID,
        sessionID: captured.sessionID,
        sessionSampler: captured.sessionSampler,
        viewID: captured.viewID,
        userActionID: currentActionID,
        viewServerTimeOffset: captured.viewServerTimeOffset,
        viewPath: captured.viewPath,
        viewName: captured.viewName
    )
}
