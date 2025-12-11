/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

/// Displays a view with buttons that trigger several variations of alerts and confirmation dialogs.
///
/// The equivalent to ``RUMAlertRootViewController`` in SwiftUI.
@available(iOS 13, tvOS 13, *)
struct RUMAlertSwiftUI: View {
    @State private var showingSimpleAlert = false
    @State private var showingAlertManyButtons = false
    @State private var showingAlertWithTextField = false
    @State private var showingSimpleActionSheet = false
    @State private var showingManyButtonsActionSheet = false

    @State private var textFieldContent = ""

    var body: some View {
        if #available(iOS 15.0, *) {
            VStack {
                Button("Show Simple Alert") { showingSimpleAlert = true }
                Button("Show Alert Many Buttons") { showingAlertManyButtons = true }
                Button("Show Alert Text Field") { showingAlertWithTextField = true }
                Button("Show Simple Action Sheet") { showingSimpleActionSheet = true }
                Button("Show Many Buttons Action Sheet") { showingManyButtonsActionSheet = true }
            }
            .alert("This is an alert title.", isPresented: $showingSimpleAlert) {
                Button("Cancel", role: .cancel) { }
                Button("OK") { }
            }
            .alert("This is an alert title.", isPresented: $showingAlertManyButtons) {
                Button("Cancel", role: .cancel) { }
                Button("OK") { }
                Button("Delete", role: .destructive) { }
                if #available(iOS 26.0, tvOS 26.0, *) {
                    Button("More Info", role: .confirm) { }
                    Button("Close", role: .close) { }
                }
            }
            .alert("This is an alert title.", isPresented: $showingAlertWithTextField) {
                TextField("Name", text: $textFieldContent)
                Button("Cancel", role: .cancel) { }
                Button("OK") { }
            }
            .confirmationDialog("This is an alert title.", isPresented: $showingSimpleActionSheet) {
                Button("Cancel", role: .cancel) { }
                Button("OK") { }
            }
            .confirmationDialog("This is an alert title.", isPresented: $showingManyButtonsActionSheet) {
                Button("Cancel", role: .cancel) { }
                Button("OK") { }
                Button("Delete", role: .destructive) { }
                if #available(iOS 26.0, tvOS 26.0, *) {
                    Button("More Info", role: .confirm) { }
                    Button("Close", role: .close) { }
                }
            }
        } else {
            VStack {
                Button("Show Simple Alert") { showingSimpleAlert = true }
                    .alert(isPresented: $showingSimpleAlert) {
                        Alert(title: Text("This is an alert title."),
                              message: Text("A message describing the problem."),
                              primaryButton: .default(Text("OK")),
                              secondaryButton: .cancel(Text("Cancel"))
                        )
                    }
                Button("Show Alert Many Buttons") { showingAlertManyButtons = true }
                    .alert(isPresented: $showingAlertManyButtons) {
                        Alert(title: Text("This is an alert title."),
                              message: Text("A message describing the problem."),
                              primaryButton: .destructive(Text("Delete")),
                              secondaryButton: .cancel(Text("Cancel"))
                        )
                    }
                Button("Show Alert Text Field") { showingAlertWithTextField = true }
                    .alert(isPresented: $showingAlertWithTextField) {
                        // Before iOS 15 there was no way to show a pure SwiftUI alert with
                        // a text field. Therefore we show a regular alert. Make sure tests
                        // expect this.
                        Alert(title: Text("This is an alert title."),
                              message: Text("A message describing the problem."),
                              primaryButton: .default(Text("OK")),
                              secondaryButton: .cancel(Text("Cancel"))
                        )
                    }
                Button("Show Simple Action Sheet") { showingSimpleActionSheet = true }
                    .actionSheet(isPresented: $showingSimpleActionSheet) {
                        ActionSheet(title: Text("This is an alert title."),
                                    message: Text("A message describing the problem."),
                                    buttons: [
                                        .cancel(),
                                        .default(Text("OK"))
                                    ]
                        )
                    }
                Button("Show Many Buttons Action Sheet") { showingManyButtonsActionSheet = true }
                    .actionSheet(isPresented: $showingManyButtonsActionSheet) {
                        ActionSheet(title: Text("This is an alert title."),
                                    message: Text("A message describing the problem."),
                                    buttons: [
                                        .cancel(),
                                        .default(Text("OK")),
                                        .destructive(Text("Delete"))
                                    ]
                        )
                    }
            }
        }
    }
}
