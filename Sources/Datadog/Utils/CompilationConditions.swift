import Foundation

/// Swift abstraction over compiler flags set in `Active Compilation Conditions` build setting for `Datadog` target.
internal struct CompilationConditions {
    #if DD_SDK_DEVELOPMENT
    /// `true` if `DD_SDK_DEVELOPMENT` flag is set.
    static var isSDKCompiledForDevelopment: Bool = true
    #else
    /// `false` if `DD_SDK_DEVELOPMENT` flag is not set.
    static var isSDKCompiledForDevelopment: Bool = false
    #endif
}
