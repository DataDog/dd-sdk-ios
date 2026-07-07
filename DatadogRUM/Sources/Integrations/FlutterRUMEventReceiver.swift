import Foundation
import DatadogInternal

/// Receives Flutter RUM events from the message bus and writes them to the RUM
/// feature scope, enriched with the native application/session context.
/// This ensures the Flutter viewID appears in the session's view list,
/// enabling the Session Replay player to fetch segments for it.
internal struct FlutterRUMEventReceiver: FeatureMessageReceiver {
    let scope: FeatureScope

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .flutterView(.rum(event)) = message else {
            return false
        }

        scope.eventWriteContext { context, writer in
            guard
                let rumContext = context.additionalContext(ofType: RUMCoreContext.self),
                rumContext.sessionSampler.isSampled
            else {
                return
            }

            // Rewrite the event with the native application/session context
            // while preserving the Flutter viewID, so the backend indexes it
            // as part of the native RUM session.
            var enrichedEvent = event
            enrichedEvent["application"] = ["id": rumContext.applicationID]
            enrichedEvent["session"] = [
                "id": rumContext.sessionID,
                "type": "user"
            ]
            // Tag source as "flutter" so the metadata API includes it
            enrichedEvent["source"] = "flutter"

            if enrichedEvent["_dd"] == nil {
                enrichedEvent["_dd"] = [
                    "format_version": 2,
                    "document_version": 1,
                    "session": ["plan": 2]
                ]
            }

            NSLog("[DD-RUM-F] writing Flutter RUM view event for viewID=\(enrichedEvent["view"].flatMap { ($0 as? [String: Any])?["id"] } ?? "unknown")")
            writer.write(value: AnyEncodable(enrichedEvent))
        }

        return true
    }
}