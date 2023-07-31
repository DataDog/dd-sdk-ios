/// OpenTracing span reference
public struct OTReference {
    /// Type of reference
    public let type: OTReferenceType

    /// Span context that the reference points to
    public let context: OTSpanContext

    public static func child(of parent: OTSpanContext) -> OTReference {
        return OTReference(type: .childOf, context: parent)
    }

    public static func follows(from precedingContext: OTSpanContext) -> OTReference {
        return OTReference(type: .followsFrom, context: precedingContext)
    }
}

/// Enum representing the type of reference
public enum OTReferenceType: String {
    /// The CHILD_OF reference type, used to denote direct causal relationships
    case childOf = "CHILD_OF"

    /// The FOLLOWS_FROM reference type, currently used to denote all other non-causal relationships
    case followsFrom = "FOLLOWS_FROM"
}
