/// Struct that stores the shared tracer
public struct Global {
    private init() {}

    /// Shared tracer instance used throughout the app
    public static var sharedTracer: OTTracer = DDNoopGlobals.tracer
}
