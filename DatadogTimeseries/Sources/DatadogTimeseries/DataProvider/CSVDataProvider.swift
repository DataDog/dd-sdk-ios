import Foundation

class CSVDataProvider: DataProvider {
    private var samples: [Sample]
    private var index: Int = 0

    init(csvContent: String, metric: TimeseriesName) {
        var parsed: [Sample] = []
        let lines = csvContent.components(separatedBy: "\n")

        for line in lines.dropFirst() { // skip header
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let columns = trimmed.components(separatedBy: ",")
            guard columns.count == 3 else { continue }

            guard columns[1] == metric.rawValue else { continue }
            guard let timestamp = Int64(columns[0]),
                  let value = Double(columns[2]) else { continue }

            parsed.append(Sample(timestamp: timestamp, value: value))
        }

        self.samples = parsed
    }

    func read() -> Sample? {
        guard index < samples.count else { return nil }
        let sample = samples[index]
        index += 1
        return sample
    }
}
