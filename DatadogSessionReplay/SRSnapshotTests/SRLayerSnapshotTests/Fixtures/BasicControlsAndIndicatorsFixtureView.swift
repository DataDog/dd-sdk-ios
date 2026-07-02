/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI
import UIKit

@available(iOS 16.0, *)
internal struct BasicControlsAndIndicatorsFixtureView: View {
    var body: some View {
        VStack(alignment: .leading) {
            toggles
            sliders
            progressIndicators
        }
        .padding()
    }

    private var toggles: some View {
        VStack(alignment: .leading) {
            Toggle("On", isOn: .constant(true))
            Toggle("Off", isOn: .constant(false))
            Toggle("Disabled", isOn: .constant(true))
                .disabled(true)
            Toggle("Tinted", isOn: .constant(true))
                .tint(.purple)
            Toggle("Button style", isOn: .constant(true))
                .toggleStyle(.button)
        }
    }

    private var sliders: some View {
        VStack {
            Slider(value: .constant(0.35))
            Slider(value: .constant(0.7))
                .tint(.purple)
            Slider(value: .constant(0.45))
                .disabled(true)

            if #available(iOS 26.0, *) {
                Slider(value: .constant(0.55), in: 0...1, step: 0.25) {
                    EmptyView()
                } tick: { value in
                    SliderTick(value)
                }
            }

            CustomSlider(value: 0.75)
                .frame(height: 44)
        }
    }

    private var progressIndicators: some View {
        VStack(spacing: 16) {
            StaticActivityIndicator(style: .large)
            ProgressView(value: 0.35)
            ProgressView(value: 0.6)
                .progressViewStyle(CapsuleProgressViewStyle())
        }
    }
}

@available(iOS 16.0, *)
private struct CustomSlider: UIViewRepresentable {
    let value: Float

    func makeUIView(context _: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.setMinimumTrackImage(.sliderTrack(color: .systemTeal), for: .normal)
        slider.setMaximumTrackImage(.sliderTrack(color: .systemGray5), for: .normal)
        slider.setThumbImage(.sliderThumb(fill: .systemIndigo, stroke: .white), for: .normal)
        slider.value = value
        return slider
    }

    func updateUIView(_ slider: UISlider, context _: Context) {
        slider.value = value
    }
}

@available(iOS 16.0, *)
private struct CapsuleProgressViewStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { proxy in
            let progress = CGFloat(configuration.fractionCompleted ?? 0)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.gray.opacity(0.2))
                Capsule()
                    .fill(.teal)
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 12)
    }
}

@available(iOS 16.0, *)
private struct StaticActivityIndicator: UIViewRepresentable {
    let style: UIActivityIndicatorView.Style

    func makeUIView(context _: Context) -> UIActivityIndicatorView {
        let view = UIActivityIndicatorView(style: style)
        view.hidesWhenStopped = false
        view.stopAnimating()
        return view
    }

    func updateUIView(_ view: UIActivityIndicatorView, context _: Context) {
        view.hidesWhenStopped = false
        view.stopAnimating()
    }
}

@available(iOS 16.0, *)
private extension UIImage {
    static func sliderTrack(color: UIColor) -> UIImage {
        let size = CGSize(width: 12, height: 8)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            color.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4).fill()
        }
        .resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 6))
    }

    static func sliderThumb(fill: UIColor, stroke: UIColor) -> UIImage {
        let size = CGSize(width: 28, height: 28)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            let path = UIBezierPath(ovalIn: rect)

            fill.setFill()
            path.fill()

            stroke.setStroke()
            path.lineWidth = 3
            path.stroke()
        }
    }
}
