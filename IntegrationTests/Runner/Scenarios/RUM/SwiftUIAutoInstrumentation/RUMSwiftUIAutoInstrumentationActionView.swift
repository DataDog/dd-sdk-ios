/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

// MARK: - SwiftUIAutoInstrumentationActionViewScenario

@available(iOS 14.0, *)
class SwiftUIAutoInstrumentationActionView: UIHostingController<ActionsView> {
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder, rootView: ActionsView())
    }
}

@available(iOS 14.0, *)
struct ActionsView: View {
    @State private var isToggleOn = false
    @State private var sliderValue: Double = 0.5
    @State private var stepperValue = 5
    @State private var pickerSelection = 1
    @State private var text = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("SwiftUI Interactive Components")
                    .font(.title)
                
                // Button
                Button("Button") {}
                    .accessibilityIdentifier("main_button")
                
                // Navigation Link
                NavigationLink("Navigate to Detail") {
                    Text("Detail View")
                }
                .accessibilityIdentifier("navigation-link")
                
                // Toggle
                Toggle("Toggle Switch", isOn: $isToggleOn)
                    .accessibilityIdentifier("toggle")
                
                // Slider
#if os(iOS)
                Slider(value: $sliderValue)
                    .accessibilityIdentifier("slider")
#endif
                
                // Stepper
#if os(iOS)
                Stepper("Value: \(stepperValue)", value: $stepperValue, in: 0...10)
                    .accessibilityIdentifier("stepper")
#endif
                
                // Picker
                Picker("Selection", selection: $pickerSelection) {
                    Text("Option 1").tag(1)
                    Text("Option 2").tag(2)
                }
                .pickerStyle(.segmented)
                
                // TextField
                TextField("Enter text", text: $text)
#if os(iOS)
                    .textFieldStyle(.roundedBorder)
#endif
                
                // Menu
                if #available(iOS 14.0, *) {
                    Menu("Open Menu") {
                        Button("Menu Item 1") {}
                            .accessibilityIdentifier("menu_item_1")
                        Button("Menu Item 2") {}
                            .accessibilityIdentifier("menu_item_2")
                    }
                    .accessibilityIdentifier("menu")
                }
            }
        }
        .padding(20)
    }
}
