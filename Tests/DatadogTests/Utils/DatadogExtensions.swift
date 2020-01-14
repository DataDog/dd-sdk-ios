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

    /// Returns creation date of file with given name.
    static func from(fileName: String) -> Date {
        return fileCreationDateFrom(fileName: fileName)
    }
}
