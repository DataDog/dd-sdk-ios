import Foundation

extension Optional {
    func ifNotNil(_ closure: (Wrapped) throws -> Void) rethrows {
        if case .some(let unwrappedValue) = self {
            try closure(unwrappedValue)
        }
    }
}
