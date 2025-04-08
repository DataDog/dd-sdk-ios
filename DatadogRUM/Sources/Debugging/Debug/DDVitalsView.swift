/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

@available(iOS 15.0, *)
public struct DDVitalsView: View {

    public static let height: CGFloat = 250
    private static let padding: CGFloat = 10

    @StateObject var viewModel: DDVitalsViewModel

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(viewModel: DDVitalsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack {
            // Navigation View
            self.topView
                .padding(Self.padding)

            // Vitals
            HStack(spacing: 10) {
                self.vitalView(
                    title: "CPU",
                    value: self.viewModel.cpuValue,
                    metric: "ticks/s",
                    level: .low
                )
                self.vitalView(
                    title: "Memory",
                    value: self.viewModel.memoryValue,
                    metric: "MB",
                    level: .low
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Self.padding)

            // Timeline
            self.timelineView
                .padding(Self.padding)

            HStack {
                self.rateView(
                    title: "SlowFrame Rate",
                    value: self.viewModel.hitchesRatio > 1 ? self.viewModel.hitchesRatio : 0,
                    metric: "ms/s",
                    level: self.viewModel.hitchesRatio > 10 ? .high : .low
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                self.rateView(
                    title: "Freeze Rate",
                    value: self.viewModel.hangsRatio > 1 ? self.viewModel.hangsRatio : 0,
                    metric: "s/h",
                    level: self.viewModel.hangsRatio > 100 ? .high : .low
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding([.horizontal, .bottom], Self.padding)
        }
        .frame(height: Self.height, alignment: .topLeading)
        .background(Color.white.opacity(0.9))
        .cornerRadius(12)
        .shadow(color: .gray, radius: 12)
        .padding(Self.padding)
        .onReceive(timer) { timer in

            self.viewModel.updateView()
        }
    }
}

@available(iOS 15.0, *)
extension DDVitalsView {

    var topView: some View {
        HStack {
            Image("datadog", bundle: .module)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)

            Text(self.viewModel.viewScopeName)
                .font(.system(size: 16)).bold()
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(timeString(from: Int(self.viewModel.currentDuration)))
                .font(.system(size: 14, design: .monospaced))

            Spacer()

            Button("", systemImage: "gearshape.fill") {


            }
            .foregroundStyle(Color.purple)
            .frame(width: 32, height: 32)
        }
    }

    @ViewBuilder
    func vitalView(title: String, value: Double, metric: String, level: WarningLevel) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
            HStack(spacing: 5) {
                Circle()
                    .fill(level.color)
                    .frame(width: 10, height: 10)
                Text("\(value, specifier: "%.2f") \(metric)")
                    .font(.caption).bold()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Self.padding)
        .background(Color.gray.opacity(0.5))
        .cornerRadius(5)
    }

    @ViewBuilder
    func rateView(title: String, value: Double, metric: String, level: WarningLevel) -> some View {
        HStack {
            Circle()
                .fill(level.color)
                .frame(width: 10, height: 10)
            Text("**\(title)**\n\(value, specifier: "%.2f") \(metric)")
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var timelineView: some View {
        let barHeight: CGFloat = 40

        VStack {
            Text("Timeline")
                .font(.system(size: 10)).bold()
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .leading) {
                GeometryReader { geometry in
                    let barWidth = geometry.size.width

                    Rectangle()
                        .fill(Color.gray.opacity(0.7))
                        .frame(width: barWidth, height: barHeight)
                        .cornerRadius(5)

                    Rectangle()
                        .fill(Color.gray.opacity(0.7))
                        .frame(width: viewModel.progress * barWidth, height: barHeight)
                        .cornerRadius(6)

                    ForEach(viewModel.hangs, id: \.0.self) { marker in
                        Rectangle()
                            .fill(Color.blue.opacity(0.7))
                            .frame(
                                width: (marker.1 * 3),
                                height: barHeight
                            )
                            .cornerRadius(5)
                            .offset(x: marker.0 * barWidth)
                    }

                    ForEach(viewModel.hitches, id: \.0.self) { marker in
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: 2.0 * marker.1, height: barHeight)
                            .offset(x: marker.0 * barWidth - 1) // Centering
                    }
                }
            }
            .frame(maxHeight: barHeight)
        }
    }
}

@available(iOS 15.0, *)
private extension DDVitalsView {

    private func timeString(from seconds: Int) -> String {
        let minutes = seconds / 60
        let seconds = seconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

@available(iOS 15.0, *)
enum WarningLevel {
    case low
    case medium
    case high

    var color: Color {
        switch self {
        case .low:
            return .green
        case .medium:
            return .yellow
        case .high:
            return .red
        }
    }
}

@available(iOS 15.0, *)
#Preview {

    DDVitalsView(viewModel: DDVitalsViewModel())
}
