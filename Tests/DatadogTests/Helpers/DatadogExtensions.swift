import Foundation
@testable import Datadog

/*
 Set of Datadog domain extensions over standard types for writting more readable tests.
 Domain agnostic extensions should be put in `SwiftExtensions.swift`.
*/

extension Date {
    /// Returns name of the logs file createde at this date.
    var toFileName: String {
        return fileNameFrom(fileCreationDate: self)
    }
}

extension EncodableValue: Equatable {
    public static func == (lhs: EncodableValue, rhs: EncodableValue) -> Bool {
        return String(describing: lhs) == String(describing: rhs)
    }
}
