/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal
import QuartzCore
import SwiftUI
import TestUtilities
import Testing
import UIKit
import WebKit

@testable import DatadogSessionReplay

@Suite(.datadogTesting)
@MainActor
struct SemanticObservationTests {
    private final class DestOutView: UIView {}

    @available(iOS 26.0, *)
    private struct ScrollPocketFixture: View {
        var body: some View {
            NavigationStack {
                ScrollView {
                    Color.clear.frame(height: 2_000)
                }
                .navigationTitle("Title")
                .toolbar {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button("Refresh", systemImage: "arrow.clockwise", action: {})
                        Spacer()
                        Button("Add", systemImage: "plus", action: {})
                    }
                }
            }
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records plain layer semantics")
    func recordsPlainLayerSemantics() {
        // Given
        let layer = CALayer()

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .layer))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records linear gradient semantics")
    func recordsLinearGradientSemantics() throws {
        // Given
        let colors = [UIColor.red.cgColor, UIColor.blue.cgColor]
        let locations = [CGFloat(0.25), CGFloat(0.75)]
        let layer = CAGradientLayer()
        layer.colors = colors
        layer.locations = locations.map { NSNumber(value: Double($0)) }
        layer.startPoint = CGPoint(x: 0, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 0.5)

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: layer, context: .mockAny())

        // Then
        let gradient = try #require(
            CALayerSnapshot.SemanticObservation.GradientSemantics(
                type: .axial,
                colors: colors,
                locations: locations,
                startPoint: layer.startPoint,
                endPoint: layer.endPoint
            )
        )
        #expect(observation == .init(semantics: .gradient(gradient)))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records unsupported gradient as plain layer semantics")
    func recordsUnsupportedGradientAsPlainLayerSemantics() {
        // Given
        let layer = CAGradientLayer()
        layer.type = .radial
        layer.colors = [UIColor.red.cgColor, UIColor.blue.cgColor]

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .layer))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records masked leaf gradient as plain layer semantics")
    func recordsMaskedLeafGradientAsPlainLayerSemantics() {
        // Given
        let layer = CAGradientLayer()
        layer.colors = [UIColor.red.cgColor, UIColor.blue.cgColor]
        layer.mask = CALayer()

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .layer))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records visual effect backdrop semantics and ignores sublayers")
    func recordsVisualEffectBackdropSemanticsAndIgnoresSublayers() throws {
        // Given
        let visualEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        let backdropLayer = try #require(
            visualEffectView.layer.sublayers?.first {
                NSStringFromClass(type(of: $0)) == "UICABackdropLayer"
            }
        )

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: backdropLayer, context: .mockAny())

        // Then
        #expect(observation == .init(
            semantics: .visualEffect(.backdrop),
            ignoresSublayers: true
        ))
    }

    @available(iOS 26.0, *)
    @Test("Records scroll pockets with their rect edge and ignores sublayers")
    func recordsScrollPocketsWithTheirRectEdgeAndIgnoresSublayers() throws {
        // Given
        let viewController = UIHostingController(rootView: ScrollPocketFixture())

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        viewController.view.layoutIfNeeded()
        defer { window.isHidden = true }

        let scrollPockets = try [UIRectEdge.top, .bottom].map { edge in
            try #require(
                window.layer.firstDescendant { layer in
                    guard
                        let delegate = layer.delegate as? NSObject,
                        NSStringFromClass(type(of: delegate)) == "_UIScrollPocket",
                        let value = delegate.value(forKey: "edge") as? NSNumber
                    else {
                        return false
                    }
                    return UIRectEdge(rawValue: value.uintValue) == edge
                }
            )
        }

        // When
        let observations = scrollPockets.map {
            CALayerSnapshot.SemanticObservation(layer: $0, context: .mockAny())
        }

        // Then
        #expect(observations == [
            .init(semantics: .visualEffect(.scrollPocket(.top)), ignoresSublayers: true),
            .init(semantics: .visualEffect(.scrollPocket(.bottom)), ignoresSublayers: true)
        ])
    }

    @available(iOS 26.0, *)
    @Test("Records capture-only backdrops as compositor support")
    func recordsCaptureOnlyBackdropsAsCompositorSupport() throws {
        // Given
        let viewController = UIHostingController(rootView: ScrollPocketFixture())

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        viewController.view.layoutIfNeeded()
        defer { window.isHidden = true }

        let backdropLayer = try #require(
            window.layer.firstDescendant { layer in
                layer.responds(to: NSSelectorFromString("captureOnly"))
                    && (layer.value(forKey: "captureOnly") as? Bool) == true
            }
        )

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: backdropLayer, context: .mockAny())

        // Then
        #expect(observation == .init(
            semantics: .visualEffect(.compositorSupport),
            ignoresSublayers: true
        ))
    }

    @available(iOS 26.0, *)
    @Test("Records tab bar platter as an automatic capsule and records sublayers")
    func recordsTabBarPlatterAsAutomaticCapsuleAndRecordsSublayers() throws {
        // Given
        let tabBarController = UITabBarController()
        tabBarController.viewControllers = (0..<3).map { index in
            let viewController = UIViewController()
            viewController.tabBarItem = UITabBarItem(
                title: "Tab \(index)",
                image: UIImage(systemName: "circle"),
                tag: index
            )
            return viewController
        }

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = tabBarController
        window.makeKeyAndVisible()
        tabBarController.view.layoutIfNeeded()
        defer { window.isHidden = true }

        let platterView = try #require(
            tabBarController.tabBar.firstDescendant {
                NSStringFromClass(type(of: $0)) == "UIKit._UITabBarPlatterView"
            }
        )

        // When
        let observation = CALayerSnapshot.SemanticObservation(
            layer: platterView.layer,
            context: .mockAny()
        )

        // Then
        #expect(observation == .init(semantics: .visualEffect(.automaticCapsule)))
    }

    @available(iOS 26.0, *)
    @Test("Records platform glass interaction as an automatic capsule and records sublayers")
    func recordsPlatformGlassInteractionAsAutomaticCapsuleAndRecordsSublayers() throws {
        // Given
        let viewController = UIHostingController(rootView: ScrollPocketFixture())

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        viewController.view.layoutIfNeeded()
        defer { window.isHidden = true }

        let interactionLayer = try #require(
            window.layer.firstDescendant { layer in
                guard let view = layer.delegate as? UIView else {
                    return false
                }
                return NSStringFromClass(type(of: view)).hasSuffix("UIPlatformGlassInteractionView")
            }
        )

        // When
        let observation = CALayerSnapshot.SemanticObservation(
            layer: interactionLayer,
            context: .mockAny()
        )

        // Then
        #expect(observation == .init(semantics: .visualEffect(.automaticCapsule)))
    }

    @available(iOS 26.0, *)
    @Test("Records portal semantics")
    func recordsPortalSemantics() throws {
        // Given
        let tabBarController = UITabBarController()
        tabBarController.viewControllers = (0..<3).map { index in
            let viewController = UIViewController()
            viewController.tabBarItem = UITabBarItem(
                title: "Tab \(index)",
                image: UIImage(systemName: "circle"),
                tag: index
            )
            return viewController
        }

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = tabBarController
        window.makeKeyAndVisible()
        tabBarController.view.layoutIfNeeded()
        defer { window.isHidden = true }

        let portalLayer = try #require(
            tabBarController.tabBar.layer.firstDescendant {
                NSStringFromClass(type(of: $0)) == "CAPortalLayer"
                    && ($0.value(forKey: "hidesSourceLayer") as? Bool) == true
            }
        )
        let sourceLayer = try #require(portalLayer.value(forKey: "sourceLayer") as? CALayer)
        let sourceRect = sourceLayer.convert(portalLayer.bounds, from: portalLayer)
        let context = CALayerSnapshot.Context.mockAny()

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: portalLayer, context: context)

        // Then
        guard case .visualEffect(.portal(let portal)) = observation.semantics else {
            Issue.record("Expected portal semantics")
            return
        }

        #expect(portal.sourceReplayID == sourceLayer.replayID)
        #expect(portal.sourceRect == sourceRect)
        #expect(
            portal.matchesPosition
                == ((portalLayer.safeValue(forKey: "matchesPosition") as? Bool) == true)
        )
        #expect(
            portal.matchesTransform
                == ((portalLayer.safeValue(forKey: "matchesTransform") as? Bool) == true)
        )
        #expect(
            portal.matchesOpacity
                == ((portalLayer.safeValue(forKey: "matchesOpacity") as? Bool) == true)
        )
        #expect(observation.ignoresSublayers)
    }

    @available(iOS 26.0, *)
    @Test("Records tab bar compositor infrastructure as compositor support")
    func recordsTabBarCompositorInfrastructureAsCompositorSupport() throws {
        // Given
        let tabBarController = UITabBarController()
        tabBarController.viewControllers = (0..<3).map { index in
            let viewController = UIViewController()
            viewController.tabBarItem = UITabBarItem(
                title: "Tab \(index)",
                image: UIImage(systemName: "circle"),
                tag: index
            )
            return viewController
        }

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = tabBarController
        window.makeKeyAndVisible()
        tabBarController.view.layoutIfNeeded()
        defer { window.isHidden = true }

        let sdfLayer = try #require(
            tabBarController.tabBar.layer.firstDescendant {
                NSStringFromClass(type(of: $0)) == "CASDFLayer"
            }
        )
        let sdfElementLayer = try #require(
            tabBarController.tabBar.layer.firstDescendant {
                NSStringFromClass(type(of: $0)) == "CASDFElementLayer"
            }
        )
        let destinationOutLayer = try #require(
            tabBarController.tabBar.layer.firstDescendant {
                guard let delegate = $0.delegate else {
                    return false
                }
                return NSStringFromClass(type(of: delegate)).hasSuffix("DestOutView")
            }
        )
        let nonHidingPortalLayer = try #require(
            window.layer.firstDescendant {
                NSStringFromClass(type(of: $0)) == "CAPortalLayer"
                    && ($0.value(forKey: "hidesSourceLayer") as? Bool) != true
            }
        )

        // When
        let sdfObservation = CALayerSnapshot.SemanticObservation(layer: sdfLayer, context: .mockAny())
        let sdfElementObservation = CALayerSnapshot.SemanticObservation(layer: sdfElementLayer, context: .mockAny())
        let destinationOutObservation = CALayerSnapshot.SemanticObservation(
            layer: destinationOutLayer,
            context: .mockAny()
        )
        let nonHidingPortalObservation = CALayerSnapshot.SemanticObservation(
            layer: nonHidingPortalLayer,
            context: .mockAny()
        )

        // Then
        let expectedSDFObservation = CALayerSnapshot.SemanticObservation(
            semantics: .visualEffect(.compositorSupport)
        )
        #expect(sdfObservation == expectedSDFObservation)
        #expect(sdfElementObservation == expectedSDFObservation)
        #expect(destinationOutObservation == .init(
            semantics: .visualEffect(.compositorSupport),
            ignoresSublayers: true
        ))
        #expect(nonHidingPortalObservation == .init(
            semantics: .visualEffect(.compositorSupport),
            ignoresSublayers: true
        ))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records application DestOutView as plain layer semantics")
    func recordsApplicationDestOutViewAsPlainLayerSemantics() {
        // Given
        let view = DestOutView()

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: view.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .layer))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Rejects gradient semantics with fewer than two colors")
    func rejectsGradientSemanticsWithFewerThanTwoColors() {
        // Given
        let colors = [UIColor.red.cgColor]

        // When
        let gradient = CALayerSnapshot.SemanticObservation.GradientSemantics(
            type: .axial,
            colors: colors,
            locations: nil,
            startPoint: CGPoint(x: 0.5, y: 0),
            endPoint: CGPoint(x: 0.5, y: 1)
        )

        // Then
        #expect(gradient == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Rejects gradient semantics with mismatched locations")
    func rejectsGradientSemanticsWithMismatchedLocations() {
        // Given
        let colors = [UIColor.red.cgColor, UIColor.blue.cgColor]

        // When
        let gradient = CALayerSnapshot.SemanticObservation.GradientSemantics(
            type: .axial,
            colors: colors,
            locations: [0],
            startPoint: CGPoint(x: 0.5, y: 0),
            endPoint: CGPoint(x: 0.5, y: 1)
        )

        // Then
        #expect(gradient == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records activity indicators as plain layers and ignores sublayers")
    func recordsActivityIndicatorsAsPlainLayersAndIgnoresSublayers() {
        // Given
        let activityIndicator = UIActivityIndicatorView(style: .medium)

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: activityIndicator.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .layer, ignoresSublayers: true))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records label semantics and ignores sublayers")
    func recordsLabelSemanticsAndIgnoresSublayers() {
        // Given
        let font = UIFont.systemFont(ofSize: 14)
        let label = UILabel()
        label.text = "Hello"
        label.textColor = .red
        label.textAlignment = .center
        label.font = font
        label.adjustsFontSizeToFitWidth = true
        label.lineBreakMode = .byTruncatingMiddle

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: label.layer, context: .mockAny())

        // Then
        #expect(observation == .init(
            semantics: .label(
                .init(
                    text: "Hello",
                    textColor: .red,
                    textAlignment: .center,
                    font: font,
                    adjustsFontSizeToFitWidth: true,
                    lineBreakMode: .byTruncatingMiddle
                )
            ),
            ignoresSublayers: true
        ))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records single run attributed label semantics")
    func recordsSingleRunAttributedLabelSemantics() {
        // Given
        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: "Hello",
            attributes: [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.red
            ]
        )

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: label.layer, context: .mockAny())

        // Then
        #expect(observation == .init(
            semantics: .label(
                .init(
                    text: "Hello",
                    textColor: label.textColor,
                    textAlignment: label.textAlignment,
                    font: label.font,
                    adjustsFontSizeToFitWidth: label.adjustsFontSizeToFitWidth,
                    lineBreakMode: label.lineBreakMode
                )
            ),
            ignoresSublayers: true
        ))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records bold labels as layer semantics")
    func recordsBoldLabelsAsLayerSemantics() {
        // Given
        let label = UILabel()
        label.text = "Hello"
        label.font = .boldSystemFont(ofSize: 14)

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: label.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .layer))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records non-regular system font labels as layer semantics")
    func recordsNonRegularSystemFontLabelsAsLayerSemantics() {
        // Given
        let label = UILabel()
        label.text = "Hello"
        label.font = .systemFont(ofSize: 14, weight: .medium)

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: label.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .layer))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records italic labels as layer semantics")
    func recordsItalicLabelsAsLayerSemantics() {
        // Given
        let label = UILabel()
        label.text = "Hello"
        label.font = .italicSystemFont(ofSize: 14)

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: label.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .layer))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records non-system font labels as layer semantics")
    func recordsNonSystemFontLabelsAsLayerSemantics() {
        // Given
        let label = UILabel()
        label.text = "Hello"
        label.font = .monospacedSystemFont(ofSize: 14, weight: .regular)

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: label.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .layer))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records underlined single run attributed labels as layer semantics")
    func recordsUnderlinedSingleRunAttributedLabelsAsLayerSemantics() {
        // Given
        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: "Hello",
            attributes: [
                .font: UIFont.systemFont(ofSize: 14),
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        )

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: label.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .layer))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records multi run attributed label as layer semantics")
    func recordsMultiRunAttributedLabelAsLayerSemantics() {
        // Given
        let label = UILabel()
        let attributedText = NSMutableAttributedString(string: "Hello")
        attributedText.addAttribute(.foregroundColor, value: UIColor.red, range: NSRange(location: 0, length: 2))
        attributedText.addAttribute(.foregroundColor, value: UIColor.blue, range: NSRange(location: 2, length: 3))
        label.attributedText = attributedText

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: label.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .layer))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records image semantics and ignores sublayers")
    func recordsImageSemanticsAndIgnoresSublayers() {
        // Given
        let imageView = UIImageView(image: UIImage())
        imageView.isHighlighted = true

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: imageView.layer, context: .mockAny())

        // Then
        #expect(observation == .init(
            semantics: .image(
                .init(hasContent: true, isContextual: false)
            ),
            ignoresSublayers: true
        ))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records progress view as layer semantics ignoring image privacy")
    func recordsProgressViewAsLayerSemanticsIgnoringImagePrivacy() {
        // Given
        let progressView = UIProgressView()
        progressView.progress = 0.75

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: progressView.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .layer, ignoresImagePrivacy: true))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records slider as layer semantics ignoring image privacy")
    func recordsSliderAsLayerSemanticsIgnoringImagePrivacy() {
        // Given
        let slider = UISlider()

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: slider.layer, context: .mockAny())

        // Then
        let expected = CALayerSnapshot.SemanticObservation(
            semantics: .layer,
            ignoresImagePrivacy: true
        )

        #expect(observation == expected)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records button as layer semantics ignoring image privacy")
    func recordsButtonAsLayerSemanticsIgnoringImagePrivacy() {
        // Given
        let button = UIButton()

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: button.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .layer, ignoresImagePrivacy: true))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records stepper as layer semantics ignoring image privacy")
    func recordsStepperAsLayerSemanticsIgnoringImagePrivacy() {
        // Given
        let stepper = UIStepper()

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: stepper.layer, context: .mockAny())

        // Then
        #expect(observation == .init(
            semantics: .layer,
            ignoresImagePrivacy: true
        ))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records text view input semantics and records sublayers")
    func recordsTextViewInputSemanticsAndRecordsSublayers() {
        // Given
        let textView = UITextView()
        textView.text = "Body"
        textView.isEditable = false
        textView.isSecureTextEntry = true

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: textView.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .textInput(
            .init(
                isSensitiveText: true,
                isEditable: false,
                isEmpty: false
            )
        )))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records empty text view input semantics")
    func recordsEmptyTextViewInputSemantics() {
        // Given
        let textView = UITextView()

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: textView.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .textInput(
            .init(
                isSensitiveText: false,
                isEditable: true,
                isEmpty: true
            )
        )))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records nil text view input semantics")
    func recordsNilTextViewInputSemantics() {
        // Given
        let textView = UITextView()
        textView.text = nil

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: textView.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .textInput(
            .init(
                isSensitiveText: false,
                isEditable: true,
                isEmpty: true
            )
        )))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records text field input semantics and records sublayers")
    func recordsTextFieldInputSemanticsAndRecordsSublayers() {
        // Given
        let textField = UITextField()
        textField.text = "Value"
        textField.placeholder = "Placeholder"
        textField.isSecureTextEntry = true

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: textField.layer, context: .mockAny())

        // Then
        #expect(observation == .init(
            semantics: .textInput(
                .init(
                    isSensitiveText: true,
                    isEditable: true,
                    isEmpty: false
                )
            ),
            ignoresImagePrivacy: true
        ))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records empty text field input semantics")
    func recordsEmptyTextFieldInputSemantics() {
        // Given
        let textField = UITextField()
        textField.placeholder = "Placeholder"

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: textField.layer, context: .mockAny())

        // Then
        #expect(observation == .init(
            semantics: .textInput(
                .init(
                    isSensitiveText: false,
                    isEditable: true,
                    isEmpty: true
                )
            ),
            ignoresImagePrivacy: true
        ))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records switch as layer semantics")
    func recordsSwitchAsLayerSemantics() {
        // Given
        let switchControl = UISwitch()

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: switchControl.layer, context: .mockAny())

        // Then
        let expected = CALayerSnapshot.SemanticObservation(
            semantics: .layer,
            ignoresImagePrivacy: true
        )

        #expect(observation == expected)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records web view semantics and caches web view")
    func recordsWebViewSemanticsAndCachesWebView() {
        // Given
        let webView = WKWebView()
        let webViewCache = NSHashTable<WKWebView>.weakObjects()
        let context = CALayerSnapshot.Context.mockAny(webViewCache: webViewCache)

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: webView.layer, context: context)

        // Then
        #expect(
            observation == .init(
                semantics: .webView(.init(slotID: webView.hash, slotFrame: webView.frame)),
                ignoresSublayers: true
            )
        )
        #expect(webViewCache.allObjects.first === webView)
    }
}

@available(iOS 26.0, *)
private extension UIView {
    func firstDescendant(where predicate: (UIView) -> Bool) -> UIView? {
        for subview in subviews {
            if predicate(subview) {
                return subview
            }
            if let match = subview.firstDescendant(where: predicate) {
                return match
            }
        }
        return nil
    }
}

@available(iOS 26.0, *)
private extension CALayer {
    func firstDescendant(where predicate: (CALayer) -> Bool) -> CALayer? {
        for sublayer in sublayers ?? [] {
            if predicate(sublayer) {
                return sublayer
            }
            if let match = sublayer.firstDescendant(where: predicate) {
                return match
            }
        }
        return nil
    }
}

#endif
