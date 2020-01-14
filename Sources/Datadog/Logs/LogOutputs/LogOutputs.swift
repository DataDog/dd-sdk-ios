import Foundation

/// Type writting logs to some destination.
internal protocol LogOutput {
    func write(log: Log)
}
