/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */
import Foundation

public class CSVDataProvider: DataProvider {
    private var samples: [Sample]
    private var index: Int = 0

    public init(csvContent: String, metric: TimeseriesName) {
        var parsed: [Sample] = []
        let lines = csvContent.components(separatedBy: "
")

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

    public func read() -> Sample? {
        guard index < samples.count else { return nil }
        let sample = samples[index]
        index += 1
        return sample
    }
}
