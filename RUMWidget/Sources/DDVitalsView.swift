/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

@available(iOS 15.0, *)
public struct DDVitalsView: View {
    public static let height: CGFloat = 270
    private static let padding: CGFloat = 10

    @StateObject var viewModel: DDVitalsViewModel

    @State var isShowingConfigView: Bool

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(viewModel: DDVitalsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        isShowingConfigView = false
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.7)
            VStack {
                // Navigation View
                topView
                    .padding(Self.padding)

                Spacer()

                if self.isShowingConfigView {
                    RUMConfigView(viewModel: RUMConfigViewModel(configuration: viewModel.configuration))
                        .padding(.horizontal, Self.padding)
                } else {
                    self.rumVitalsView
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.horizontal, Self.padding)
                }
            }
        }
        .frame(height: Self.height, alignment: .topLeading)
        .cornerRadius(12)
        .shadow(color: .gray, radius: 12)
        .padding(Self.padding)
        .onReceive(timer) { _ in
            viewModel.updateView()
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

            Text(self.isShowingConfigView ? "Settings" : self.viewModel.viewScopeName)
                .font(.system(size: 16)).bold()
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .foregroundStyle(.white)

            Text(timeString(from: Int(self.viewModel.currentDuration)))
                .font(.system(size: 14, design: .monospaced))
                .opacity(self.isShowingConfigView ? 0 : 1)
                .foregroundStyle(.white)

            Spacer()

            VStack {
                Button("", systemImage: "gearshape.fill") {
                    withAnimation {
                        isShowingConfigView.toggle()
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
            }
        }
    }

    var rumVitalsView: some View {
        VStack(spacing: 10) {
            // Vitals
            HStack(spacing: 10) {
                vitalView(
                    title: "CPU",
                    value: viewModel.cpuValue,
                    metric: "%",
                    level: viewModel.levelFor(cpu: viewModel.cpuValue)
                )
                vitalView(
                    title: "Memory",
                    value: viewModel.memoryValue,
                    metric: "MB",
                    level: viewModel.levelFor(memory: viewModel.memoryValue)
                )
                vitalView(
                    title: "Stack",
                    value: viewModel.threadsCount,
                    metric: "threads",
                    level: viewModel.levelFor(threads: viewModel.threadsCount)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Timeline
            timelineView(title: "RUM Timeline", progress: self.viewModel.progress, events: self.viewModel.rumEvents)

            Divider()

            HStack {
                rateView(
                    title: "SlowFrame Rate",
                    value: viewModel.hitchesRatio > 1 ? viewModel.hitchesRatio : 0,
                    metric: "ms/s",
                    level: viewModel.hitchesRatio > 10 ? .high : .low
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                rateView(
                    title: "Freeze Rate",
                    value: viewModel.hangsRatio > 1 ? viewModel.hangsRatio : 0,
                    metric: "s/h",
                    level: viewModel.hangsRatio > 100 ? .high : .low
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    func vitalView(title: String, value: Int, metric: String, level: WarningLevel) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white)
            HStack(spacing: 5) {
                Circle()
                    .fill(level.color)
                    .frame(width: 10, height: 10)
                Text("\(value < 10 ? "0" : "")\(value) \(metric)")
                    .font(.system(size: 12, design: .monospaced)).bold()
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Self.padding)
        .background(Color.black.opacity(0.6))
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
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func timelineView(title: String, progress: CGFloat, events: [TimelineEvent]) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 10)).bold()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 5)
                .foregroundStyle(.white)

            timelineView(progress: progress, events: events)

            HStack(spacing: 2) {
                Circle()
                    .fill(.blue)
                    .frame(width: 10, height: 10)
                Text("User action")
                    .font(.system(size: 8))
                    .foregroundStyle(.white)
                Rectangle()
                    .fill(Color("purple_top", bundle: .module))
                    .frame(width: 10, height: 10)
                    .padding(.leading, 5)
                Text("Network resource")
                    .font(.system(size: 8))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    func timelineView(progress: CGFloat, events: [TimelineEvent]) -> some View {
        let barHeight: CGFloat = 40

        ZStack(alignment: .leading) {
            GeometryReader { geometry in
                let barWidth = geometry.size.width
                let barHeight = geometry.size.height

                Rectangle()
                    .fill(Color.gray.opacity(0.7))
                    .frame(width: barWidth, height: barHeight)
                    .cornerRadius(5)

                Rectangle()
                    .fill(Color.gray.opacity(0.7))
                    .frame(width: viewModel.progress * barWidth, height: barHeight)
                    .cornerRadius(6)

                ForEach(events) { marker in

                    switch marker.event {
                    case .userAction:
                        Circle()
                            .fill(marker.color)
                            .frame(width: 10, height: 10)
                            .offset(x: marker.start * barWidth - 5, y: (barHeight/2) - 5)
                    case .resource:
                        Rectangle()
                            .fill(marker.color)
                            .frame(width: 10, height: 10)
                            .offset(x: marker.start * barWidth - 5, y: barHeight - 10)
                    default:
                        Rectangle()
                            .fill(marker.color)
                            .frame(width: 2.0 * marker.duration, height: barHeight)
                            .offset(x: marker.start * barWidth - 1) // Centering
                    }
                }
            }
        }
        .frame(maxHeight: barHeight)
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
                .green
        case .medium:
                .yellow
        case .high:
                .red
        }
    }
}

private extension TimelineEvent {
    @available(iOS 13.0, *)
    var color: Color {
        switch event {
        case .viewHitch:
            return .orange
        case .appHang:
            return .red
        case .userAction:
            return .blue
        case .resource:
            return Color("purple_top", bundle: .module)
        }
    }
}

@available(iOS 15.0, *)
#Preview {
    DDVitalsView(viewModel: DDVitalsViewModel(configuration: .init(clientToken: "dummy", env: "dummy")))
}
