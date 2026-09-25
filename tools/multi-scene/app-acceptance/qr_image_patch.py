"""Add a photo-library QR input to the existing validation app login screen."""
from pathlib import Path

HERE = Path(__file__).resolve().parent
QR_VIEW = 'Targets/Feature/Login/UI/QRCode Login/QRCodeScannerView.swift'


def render(text, replace):
    text = replace(text, 'import SwiftUI', 'import PhotosUI\nimport SwiftUI')
    text = replace(text, '    @State private var showQRCodeOnboarding: Bool = false', '''    @State private var showQRCodeOnboarding: Bool = false
    @State private var showImagePicker = false
    @State private var selectedQRCodeImage: PhotosPickerItem?
    @State private var isLoadingQRCodeImage = false
    @State private var didOpenQRCode = false''')
    text = replace(text, 'QRCodeScanner(isPaused: showQRCodeOnboarding) { result in', '''QRCodeScanner(isPaused: showQRCodeOnboarding || showImagePicker || isLoadingQRCodeImage || didOpenQRCode) { result in
                guard !showImagePicker, !isLoadingQRCodeImage, !didOpenQRCode else { return }''')
    text = replace(text, '''                    guard let url = URL(string: urlString) else {
                        handle(.badURL)
                        return
                    }
                    openURL(url)
                    dismiss()''', '                    openQRCode(urlString)')
    text = replace(text, '''                Button(L10n.qrCodeLoginCameraActionInfo) {
                    showQRCodeOnboarding = true
                }
                .font(.title3.bold())
                .padding(.bottom, 72)''', '''                VStack(spacing: 20) {
                    Button("Choose QR Code Image", systemImage: "photo") {
                        showImagePicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoadingQRCodeImage || didOpenQRCode)

                    if isLoadingQRCodeImage {
                        ProgressView("Reading QR code…")
                            .tint(.white)
                            .foregroundStyle(.white)
                    }

                    Button(L10n.qrCodeLoginCameraActionInfo) {
                        showQRCodeOnboarding = true
                    }
                    .font(.title3.bold())
                }
                .padding(.bottom, 72)''')
    text = replace(text, '            .trackView(name: .qrCodeScannerView)', '''            .photosPicker(isPresented: $showImagePicker, selection: $selectedQRCodeImage, matching: .images, preferredItemEncoding: .current)
            .task(id: selectedQRCodeImage) {
                guard let item = selectedQRCodeImage else { return }
                isLoadingQRCodeImage = true
                defer {
                    if selectedQRCodeImage == item {
                        selectedQRCodeImage = nil
                        isLoadingQRCodeImage = false
                    }
                }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw QRCodeImageDecoder.Failure.unreadableImage
                    }
                    try Task.checkCancellation()
                    let decoding = Task.detached(priority: .userInitiated) {
                        try QRCodeImageDecoder.message(in: data)
                    }
                    let message = try await withTaskCancellationHandler {
                        try await decoding.value
                    } onCancel: {
                        decoding.cancel()
                    }
                    try Task.checkCancellation()
                    openQRCode(message)
                } catch {
                    if !Task.isCancelled { handle(.badURL) }
                }
            }
            .trackView(name: .qrCodeScannerView)''')
    text = replace(text, '    private func handle(_ error: QRCodeScannerError) {', '''    private func openQRCode(_ message: String) {
        guard !didOpenQRCode else { return }
        guard let url = URL(string: message) else {
            handle(.badURL)
            return
        }
        didOpenQRCode = true
        openURL(url)
        dismiss()
    }

    private func handle(_ error: QRCodeScannerError) {''')
    # The existing file already belongs to LoginUI; no project membership change.
    decoder = (HERE / 'QRCodeImageDecoder.swift').read_text()
    return replace(text, '#endif\n// swiftlint:enable observableobject_mainactor',
                   decoder + '\n#endif\n// swiftlint:enable observableobject_mainactor')
