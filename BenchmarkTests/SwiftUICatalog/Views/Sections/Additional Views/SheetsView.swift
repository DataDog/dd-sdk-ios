//
//  SheetsView.swift
//  SwiftUICatalog
//
//  Created by Barbara Rodeker on 12.07.21.
//

import SwiftUI

///
/// Examples on how to make use of sheets in SwiftUI
/// OFFICIAL DOCUMENTATION https://developer.apple.com/documentation/swiftui/view/sheet(ispresented:ondismiss:content:)
///
struct SheetsView: View {
    
    // MARK: - Properties
    
    @State private var showingSheet = false
    @State private var showingSheet2 = false
    @State private var showingSheet3 = false
    @State private var showingSheet4 = false

    // MARK: - Body
    
    
    var body: some View {
        PageContainer(content:
                        ScrollView {
            Spacer()
            buttonSheet1
            Spacer()
            buttonSheet2
            Spacer()
            buttonSheet3
            Spacer()
            buttonSheet4
        }
        )
        
    }
    
    // MARK: - Functions
    
    private var buttonSheet1: some View {
        Button("Show single button Sheet") {
            showingSheet.toggle()
        }
        .padding()
        .modifier(RoundedBordersModifier(radius: 8, lineWidth: 1))
        .modifier(ButtonFontModifier())
        .sheet(isPresented: $showingSheet) {
            SingleButtonBasicSheet()
        }
        .padding(20)
        .font(.largeTitle)
    }
    
    private var buttonSheet2: some View {
        Button("Show multitext Sheet") {
            showingSheet2.toggle()
        }
        .padding()
        .modifier(RoundedBordersModifier(radius: 8, lineWidth: 1))
        .modifier(ButtonFontModifier())
        .sheet(isPresented: $showingSheet2,
               onDismiss: didDismiss) {
            sheetContentExample
        }
               .padding(20)
               .font(.largeTitle)
    }

    private var buttonSheet3: some View {
        Button("Show Sheet with standard detents") {
            showingSheet3.toggle()
        }
        .padding()
        .modifier(RoundedBordersModifier(radius: 8, lineWidth: 1))
        .modifier(ButtonFontModifier())
        .sheet(isPresented: $showingSheet3,
               onDismiss: didDismiss) {
            sheetContentExample
                .presentationDetents([.medium, .large])
        }
        .padding(20)
        .font(.largeTitle)
    }

    private var buttonSheet4: some View {
        Button("Show Sheet with fraction detents") {
            showingSheet4.toggle()
        }
        .padding()
        .modifier(RoundedBordersModifier(radius: 8, lineWidth: 1))
        .modifier(ButtonFontModifier())
        .sheet(isPresented: $showingSheet4,
               onDismiss: didDismiss) {
            sheetContentExample
                .presentationDetents([.fraction(0.2), .fraction(0.6), .fraction(1.0)])
        }
        .padding(20)
        .font(.largeTitle)
    }

    private func didDismiss() {
        // Handle the dismissing action.
    }
    
    private var sheetContentExample: some View {
        ScrollView {
            VStack(alignment: .center) {
                Text("Sheet example")
                    .font(.title)
                    .padding(50)
                Image(systemName: "flag.pattern.checkered")
                    .resizable()
                    .frame(width: 200, height: 200)
                Text("""
                                description text.
                                """)
                .padding(50)
                Button("CTA Button",
                       action: {
                    showingSheet2.toggle()
                }
                )
                .font(.title)
                .padding()
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.primary,
                                lineWidth: 1)
                )
            }
        }
    }
}

// MARK: - HASHABLE

extension SingleButtonBasicSheet {
    
    static func == (lhs: SingleButtonBasicSheet, rhs: SingleButtonBasicSheet) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}

struct SingleButtonBasicSheet: View, Comparable {
    
    // MARK: - Properties
    let id: String = "SheetView"
    
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.dismiss) var dismiss
    
    // MARK: - Body
    
    
    var body: some View {
        PageContainer(content:
                        VStack(alignment: .center) {
            Button("Press to dismiss") {
                presentationMode.wrappedValue.dismiss()
            }
            .font(.title)
            .padding()
            .foregroundColor(.white)
            .background(Color.black)
            .cornerRadius(6)
        }
            .frame(maxHeight: .infinity)
        )
        // end of page container
    }
}


#Preview {
        SheetsView()
}
