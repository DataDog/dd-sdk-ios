import Foundation

public protocol DataProvider {
    func read() -> Sample?
}
