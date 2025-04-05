/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

@available(iOS 15.0, *)
public struct ViewHitchesOverlayView: View {

    @StateObject var viewModel: ViewHitchesViewModel

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(viewModel: ViewHitchesViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack {

            Text("**Screen**: \(self.viewModel.viewScopeName)")
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.top, .horizontal])

            ZStack(alignment: .leading) {
                GeometryReader { geometry in
                    let barWidth = geometry.size.width
                    let barHeight: CGFloat = 40

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
            .padding([.horizontal, .bottom])

            HStack {

                Text("**Slow Frame Rate**: \(self.viewModel.hitchesRatio > 1 ? self.viewModel.hitchesRatio : 0, specifier: "%.2f") ms/s")
                    .font(.caption)
                    .foregroundColor(self.viewModel.hitchesRatio > 10 ? .red : .green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                Text(timeString(from: Int(self.viewModel.currentDuration)))
                    .font(.system(size: 14, design: .monospaced))
            }
            .padding(.horizontal)

            Text("**Freeze Rate**: \(self.viewModel.hangsRatio > 1 ? self.viewModel.hangsRatio : 0, specifier: "%.2f") s/h")
                .font(.caption)
                .foregroundColor(self.viewModel.hangsRatio > 100 ? .red : .green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal])
                .padding(.bottom, self.viewModel.metricsManager.diagnosticsString.count > 0 ? 0 : 10)

            if self.viewModel.metricsManager.diagnosticsString.count > 0 {
                ScrollView {
                    ZStack {

                        Text("**Payload**:\n\(self.viewModel.metricsManager.diagnosticsString)")
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        Button("", systemImage: "document.on.document") {
                            UIPasteboard.general.string = self.viewModel.metricsManager.diagnosticsString
                        }
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .padding([.horizontal, .bottom])
            }
        }
        .frame(height: self.viewModel.metricsManager.diagnosticsString.count > 0 ? 180 : 130, alignment: .topLeading)
        .background(Color.white.opacity(0.9))
        .cornerRadius(12)
        .shadow(color: .gray, radius: 12)
        .padding(.horizontal, 10)
        .onReceive(timer) { timer in

            self.viewModel.updateTimeline()
        }
    }

    private func timeString(from seconds: Int) -> String {
        let minutes = seconds / 60
        let seconds = seconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
