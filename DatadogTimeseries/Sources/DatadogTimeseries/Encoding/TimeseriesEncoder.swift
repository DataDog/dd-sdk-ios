import Foundation

struct TimeseriesEncoder {
    private let encoder: JSONEncoder

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    func encode(_ event: TimeseriesEvent) throws -> Data {
        try encoder.encode(event)
    }
}
