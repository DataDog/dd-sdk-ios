/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import SwiftUI
import DatadogInternal

fileprivate struct RUMDebugInfo {
    struct View {
        let name: String
        let isActive: Bool

        init(scope: RUMViewScope) {
            self.name = scope.viewName
            self.isActive = scope.isActiveView
        }
    }

    let views: [View]

    init(applicationScope: RUMApplicationScope) {
        self.views = (applicationScope.activeSession?.viewScopes ?? [])
            .map { View(scope: $0) }
    }
}

internal class RUMDebugging {
    /// An overlay window that renders on top of the app content. It is created lazily on first draw.
    #if os(iOS) || os(tvOS) || os(visionOS)
    private var overlayWindow: UIWindow?
    private var hostingController: UIHostingController<RUMDebugView>?
    #endif
    
    // MARK: - Initialization

    init() {
        // No device orientation notifications needed for SwiftUI
    }

    deinit {
        #if os(iOS) || os(tvOS) || os(visionOS)
        DispatchQueue.main.async { [weak overlayWindow] in
            overlayWindow?.isHidden = true
            overlayWindow?.rootViewController = nil
        }
        #endif
    }

    // MARK: - Internal

    func debug(applicationScope: RUMApplicationScope) {
        // `RUMDebugInfo` must be created on the caller thread.
        let debugInfo = RUMDebugInfo(applicationScope: applicationScope)

        DispatchQueue.main.async {
            // `RUMDebugInfo` rendering must be called on the main thread.
            self.renderOnMainThread(rumDebugInfo: debugInfo)
        }
    }

    // MARK: - Private

    private func renderOnMainThread(rumDebugInfo: RUMDebugInfo) {
        #if os(iOS) || os(tvOS) || os(visionOS)
        // Create or update the hosting controller with the new debug view
        let debugView = RUMDebugView(debugInfo: rumDebugInfo)
        
        if let existingController = hostingController {
            existingController.rootView = debugView
        } else {
            hostingController = UIHostingController(rootView: debugView)
            hostingController?.view.backgroundColor = .clear
        }
        
        // Create overlay window if needed
        if overlayWindow == nil, let windowScene = UIApplication.dd.managedShared?.connectedScenes.first as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            window.windowLevel = .alert + 1
            window.backgroundColor = .clear
            window.isUserInteractionEnabled = false
            overlayWindow = window
        }
        
        // Set up the window if not already configured
        if let window = overlayWindow, window.rootViewController == nil {
            window.rootViewController = hostingController
            window.isHidden = false
        }
        #elseif os(watchOS)
        // watchOS doesn't support overlay windows in the same way
        // Debug information would need to be presented differently on watchOS
        // This is a platform limitation
        #endif
    }
}

/// SwiftUI view that displays a single RUM view outline with its status label
internal struct RUMViewOutlineView: View {
    private struct Constants {
        static let activeViewColor = Color(red: 0.3882352941, green: 0.1725490196, blue: 0.6509803922)
        static let inactiveViewColor = Color(red: 0.6000000238, green: 0.6000000238, blue: 0.6000000238)
        static let labelHeight: CGFloat = 16
    }
    
    fileprivate let viewInfo: RUMDebugInfo.View
    let stackIndex: Int
    let stackTotal: Int
    
    private var stackOffset: CGFloat {
        CGFloat(stackIndex) * Constants.labelHeight
    }
    
    private var labelBackgroundColor: Color {
        viewInfo.isActive ? Constants.activeViewColor : Constants.inactiveViewColor
    }
    
    private var opacity: Double {
        pow(0.75, Double(stackTotal - stackIndex))
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                HStack {
                    Text(viewInfo.name)
                        .font(.system(size: Constants.labelHeight * 0.8, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                    Text(" # ")
                        .font(.system(size: Constants.labelHeight * 0.5, weight: .regular, design: .monospaced))
                        .foregroundColor(.white)
                    Text(viewInfo.isActive ? "ACTIVE" : "INACTIVE")
                        .font(.system(size: Constants.labelHeight * 0.5, weight: .regular, design: .monospaced))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: Constants.labelHeight)
                .background(labelBackgroundColor)
                .opacity(opacity)
                .offset(y: -stackOffset)
            }
        }
        .allowsHitTesting(false)
    }
}

/// SwiftUI container view for RUM debugging overlay
internal struct RUMDebugView: View {
    fileprivate let debugInfo: RUMDebugInfo
    
    var body: some View {
        ZStack {
            ForEach(0..<debugInfo.views.count, id: \.self) { index in
                RUMViewOutlineView(
                    viewInfo: debugInfo.views[index],
                    stackIndex: index,
                    stackTotal: debugInfo.views.count
                )
            }
        }
        .allowsHitTesting(false)
    }
}
