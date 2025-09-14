/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI
import TipKit

@available(iOS 15.0, *)
public struct AppLaunchView: View {
    public static let height: CGFloat = 400
    private static let padding: CGFloat = 10

    @StateObject var viewModel: AppLaunchViewModel

    @State var isShowingConfigView: Bool

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(viewModel: AppLaunchViewModel) {
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

                if isShowingConfigView {
                    RUMConfigView(viewModel: RUMConfigViewModel())
                        .padding(.horizontal, Self.padding)
                } else {
                    rumVitalsView
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
extension AppLaunchView {
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
                .foregroundStyle(.purple)
                .frame(width: 32, height: 32)
            }
        }
    }

    var rumVitalsView: some View {
        VStack(spacing: 10) {
            // Vitals
            HStack(spacing: 10) {
                vitalView(
                    title: "Time to Initial Display",
                    value: viewModel.ttid,
                    metric: "s",
                    level: viewModel.levelFor(startup: viewModel.ttid)
                )

                vitalView(
                    title: "Time to Full Display",
                    value: viewModel.ttfd,
                    metric: "s",
                    level: viewModel.levelFor(startup: viewModel.ttfd)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Launch reason: \(self.viewModel.launchReason)")
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .foregroundStyle(.white)

            Divider()
                .background(.gray)

            // Timeline
            timelineView(title: "App Launch Events", events: self.viewModel.rumEvents)

           Divider()
               .background(.gray)

            Text(self.viewModel.launchDetails)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 2) {
                ForEach(self.viewModel.rumEvents) { marker in
                    Text("\(marker.text)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(marker.id.color)
                        .padding(0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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
                    .font(.system(size: 10, design: .monospaced)).bold()
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Self.padding)
        .background(Color.black.opacity(0.3))
        .cornerRadius(5)
    }

    @ViewBuilder
    func vitalView(title: String, value: Double, metric: String, level: WarningLevel) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white)
            HStack(spacing: 5) {
                Circle()
                    .fill(level.color)
                    .frame(width: 10, height: 10)
                Text(String(format: "%.2f \(metric)", value))
                    .font(.system(size: 10, design: .monospaced)).bold()
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Self.padding)
        .background(Color.black.opacity(0.3))
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

    func timelineView(title: String, events: [AppEvent]) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 10)).bold()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 5)
                .foregroundStyle(.white)

            timelineView(events: events)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 2)
    }

    @ViewBuilder
    func timelineView(events: [AppEvent]) -> some View {
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
                    .frame(width: barWidth, height: barHeight)
                    .cornerRadius(5)

                ForEach(events) { marker in
                    Rectangle()
                        .fill(marker.id.color)
                        .frame(width: marker.width, height: barHeight)
                        .offset(x: marker.start * barWidth) // Centering

                }
            }
        }
        .frame(maxHeight: barHeight)
    }
}

@available(iOS 15.0, *)
private extension AppLaunchView {
    private func timeString(from seconds: Int) -> String {
        let minutes = seconds / 60
        let seconds = seconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}



@available(iOS 15.0, *)
#Preview {
    AppLaunchView(viewModel: AppLaunchViewModel())
}

