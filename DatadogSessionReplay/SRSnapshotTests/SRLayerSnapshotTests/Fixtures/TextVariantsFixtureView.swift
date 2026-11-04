/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

@available(iOS 16.0, *)
internal struct TextVariantsFixtureView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            UnicodeTextSamples()
            TextLayoutSamples()
        }
        .padding()
    }
}

@available(iOS 16.0, *)
private struct UnicodeTextSamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Precomposed accents and decomposed combining marks.
            Text(verbatim: "Café naïve / Cafe\u{0301} nai\u{0308}ve")

            Text(verbatim: "Αθήνα · Москва")

            Text(verbatim: "مرحبًا بالعالم — ID 123")

            Text(verbatim: "你好世界 · こんにちは世界")

            Text(verbatim: "안녕하세요 세계")

            Text(verbatim: "สวัสดีชาวโลก")

            Text(verbatim: "Order #123 · €19.99 · 50%")

            // Emoji with a skin tone, ZWJ, regional indicators, and variation selector.
            Text(verbatim: "👩🏽‍💻 🇪🇸 ❤️")
        }
        .font(.body)
    }
}

@available(iOS 16.0, *)
private struct TextLayoutSamples: View {
    private let sample = "Sample glyphs 123456"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: sample)

            Text(verbatim: sample)
                .font(.system(size: 11, design: .monospaced))

            Text(verbatim: sample)
                .font(.system(size: 8, design: .monospaced))

            Text(verbatim: sample)
                .font(.system(size: 6, design: .monospaced))

            // We don't support detecting partial glyphs. These cases verify that parent clipping
            // preserves redaction because we capture the full text layer before applying the clip.
            Text(verbatim: sample)
                .fixedSize()
                .frame(width: 155, alignment: .leading)
                .clipped()

            Text(verbatim: sample)
                .fixedSize()
                .frame(width: 155, alignment: .trailing)
                .clipped()

            Text(verbatim: sample)
                .fixedSize()
                .frame(height: 18, alignment: .top)
                .clipped()

            Text(verbatim: sample)
                .fixedSize()
                .frame(height: 18, alignment: .bottom)
                .clipped()

            Text(verbatim: sample)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 155, alignment: .leading)
        }
        .font(.system(size: 24, design: .monospaced))
    }
}
