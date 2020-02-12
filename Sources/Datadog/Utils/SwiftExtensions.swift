import Foundation

extension Optional where Wrapped == String {
    func ifNotNilNorEmpty(_ closure: (String) throws -> Void) rethrows {
        if case .some(let unwrappedValue) = self {
            try closure(unwrappedValue)
        }
    }
}
