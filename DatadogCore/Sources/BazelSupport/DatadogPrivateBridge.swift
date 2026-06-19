// Bazel build support: re-exports DatadogPrivate ObjC symbols into the DatadogCore module scope.
// In SPM, mixed-language targets get auto-generated bridging; in Bazel, targets are separate
// and this file replicates that behaviour using @_exported import.
@_exported import DatadogPrivate
