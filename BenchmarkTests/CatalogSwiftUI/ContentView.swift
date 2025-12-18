//
//  ContentView.swift
//  SwiftUICatalog
//
//  Created by Barbara Rodeker on 12.07.21.
//
// MIT License
//
// Copyright (c) 2021 Barbara M. Rodeker
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//

import SwiftUI

protocol Comparable: Hashable & Equatable & Identifiable {}

public struct ContentView: View {

    private let sectionColor = "Dark"

    private let gradient = EllipticalGradient(colors: [ Color("Medium", bundle: .module), .white],
                                              center: .topLeading,
                                              startRadiusFraction: 0.3,
                                              endRadiusFraction: 5)

    public init() {
        // change the background of all the tables
        UITableView.appearance().backgroundColor = .clear
    }
    
    // MARK: - Body
    
    public var body: some View {

        NavigationStack {
            ZStack {
                gradient
                    .ignoresSafeArea()
                
                List {
                    
                    topHeaderRow
                        .accessibilityHeading(.h1)
                    ForEach(sectionContainer.readySections) { section in
                        section.view
                            .accessibilityHeading(.h2)
                    }
                    
                }
                .scrollContentBackground(.hidden)
                .navigationTitle("SwiftUI Catalog")
                .trackView(name: "SwiftUI Catalog")
            }
            
        }
        // end of navigationview
    }
    
    // MARK: - Header sections
    
    private var topHeaderRow: some View {
        Group {
            PrivacyView(text: .maskAll) {
                Text("A catalog of components, controls, effects, styles and accessibility elements you can use to develop SwiftUI Interfaces in iOS and iPadOS.")
                    .font(.footnote)
                    .fontWeight(.light)
                    .font(.title2)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                    .foregroundColor(.white)
            }
            
            HStack(alignment: .center, spacing: 2) {
                Spacer()
                Button(action: {
                    UIApplication.shared.open(URL(string: "https://github.com/barbaramartina/swiftuicatalog/")!)
                },
                       label: {
                    Image("github", bundle: .module)
                        .resizable()
                        .frame(width: 50, height: 50)
                })
                
                Spacer()
            }
            
        }
        .listRowBackground(Color(sectionColor, bundle: .module))
        // end of section
        
    }
    
    var controls: some View {
        Section(header: Text("Controls")
            .font(.title)
            .modifier(ListSectionFontModifier())) {
                Group {
                    Link(destination: ButtonsComponentsView().trackView(name: "Buttons"),
                         label: "Buttons")
                    Link(destination: ImagesComponentView().trackView(name: "Images"),
                         label: "Images")
                    Link(destination: TextsComponentsView().trackView(name: "Texts"),
                         label: "Texts")
                    Link(destination: LabelsView().trackView(name: "Labels"),
                         label: "Labels")
                    Link(destination: MenusComponentView().trackView(name: "Menus"),
                         label: "Menus")
                }
                Group {
                    Link(destination: TogglesView().trackView(name: "Toggles"),
                         label: "Toggles")
                    Link(destination: SlidersView().trackView(name: "Sliders"),
                         label: "Sliders")
                    Link(destination: SteppersView().trackView(name: "Steppers"),
                         label: "Steppers")
                    Link(destination: PickersView().trackView(name: "Pickers"),
                         label: "Pickers")
                    Link(destination: DatePickersView().trackView(name: "Date Pickers"),
                         label: "Date Pickers")
                    Link(destination: ColorPickersView().trackView(name: "Color Pickers"),
                         label: "Color Pickers")
                    Link(destination: ProgressViews().trackView(name: "Progress View"),
                         label: "Progress View")
                }
            }
            .listRowBackground(Color(sectionColor, bundle: .module))
    }
    
    var storeKit: some View {
        Section(header: Text("Store Kit Views")
            .font(.title)
            .modifier(ListSectionFontModifier())) {
                Group {
                    Link(destination: ExampleProductView(productId: "product.consumable.example.1", productImageName: "giftcard.fill"),
                         label: "Consumable Product View").trackView(name: "Consumable Product View")
                }
            }
            .listRowBackground(Color(sectionColor, bundle: .module))

    }
    
    var layouts: some View {
        Section(header: Text("Layouts")
            .font(.title)
            .modifier(ListSectionFontModifier())) {
                Link(destination: ListsComponentView().trackView(name: "Lists"),
                     label: "Lists")
                Link(destination: StacksView().trackView(name: "Stacks"),
                     label: "Stacks")
                Link(destination: GridsView().trackView(name: "Grids"),
                     label: "Grids")
                Link(destination: ContainersView().trackView(name: "Containers"),
                     label: "Containers")
                Link(destination: ScrollViewsView().trackView(name: "Scrollviews"),
                     label: "Scrollviews")
                Link(destination: TableViews().trackView(name: "Table Views"),
                     label: "Table Views")
            }
            .listRowBackground(Color(sectionColor, bundle: .module))
    }
    
    var hierarchicalViews: some View {
        Section(header: Text("Hierarchical Views")               .font(.title)
            .modifier(ListSectionFontModifier())) {
                Link(destination: NavigationBarsComponentView().trackView(name: "Navigation"),
                     label: "Navigation")
                Link(destination: OutlinesGroupsView().trackView(name: "Outlines"),
                     label: "Outlines")
                Link(destination: DisclosureGroupsView().trackView(name: "Disclosures"),
                     label: "Disclosures")
                Link(destination: TabsView().trackView(name: "Tabs"),
                     label: "Tabs")
            }
            .listRowBackground(Color(sectionColor, bundle: .module))

    }
    
    var drawings: some View {
        Section(header: Text("Drawing and animations")
            .font(.title)
            .modifier(ListSectionFontModifier())) {
                Link(destination: CanvasView().trackView(name: "Canvas"),
                     label: "Canvas")
                Link(destination: GraphicContextsView().trackView(name: "Graphic Context"),
                     label: "Graphic Context")
                Link(destination: ShapesView().trackView(name: "Shapes"),
                     label: "Shapes")
                Link(destination: AnimationsView().trackView(name: "Animations"),
                     label: "Animations")
                Link(destination: GeometriesView().trackView(name: "Geometries"),
                     label: "Geometries")
            }
            .listRowBackground(Color(sectionColor, bundle: .module))

    }

    @available(iOS 16.0, tvOS 16.0, *)
    var charts: some View {
        Section(header: Text("Charts")
            .font(.title)
            .modifier(ListSectionFontModifier())) {
                Link(destination: ChartsViews().trackView(name: "Swift Charts"),
                     label: "Swift Charts")
            }
            .listRowBackground(Color(sectionColor, bundle: .module))

    }
    
    var gestures: some View {
        Section(header: Text("Gestures")
            .font(.title)
            .modifier(ListSectionFontModifier())) {
                Link(destination: GesturesView().trackView(name: "Gestures"),
                     label: "Gestures")
                Link(destination: ComposingGesturesView().trackView(name: "Composing Gestures"),
                     label: "Composing Gestures")
                Link(destination: SensoryFeedbackInViews().trackView(name: "Sensory Feedback"),
                     label: "Sensory Feedback")
            }
            .listRowBackground(Color(sectionColor, bundle: .module))

    }
    
    var viewModifiers: some View {
        Section(header: Text("View modifiers")
            .font(.title)
            .modifier(ListSectionFontModifier())) {
                Link(destination: TextModifiersView().trackView(name: "Text modifiers"),
                     label: "Text modifiers")
                Link(destination: EffectsModifiersView().trackView(name: "Effect modifiers"),
                     label: "Effect modifiers")
                Link(destination: LayoutModifiersView().trackView(name: "Layout modifiers"),
                     label: "Layout modifiers")
                
            }
            .listRowBackground(Color(sectionColor, bundle: .module))

    }
    
    var accessibility: some View {
        Section(header: Text("Accessibility")
            .font(.title)
            .modifier(ListSectionFontModifier())) {
                
                Link(destination: AccessibilityView().trackView(name: "Accessibility"),
                     label: "Accessibility")
            }
            .listRowBackground(Color(sectionColor, bundle: .module))

    }
    
    var statusBars: some View {
        Section(header: Text("Status and tool bars")
            .font(.title)
            .modifier(ListSectionFontModifier())) {
                Link(destination: ToolbarsComponentView().trackView(name: "Tool Bars"),
                     label: "Tool Bars")
            }
            .listRowBackground(Color(sectionColor, bundle: .module))

    }
    
    var stylingSection: some View {
        Section(header: Text("Styling")
            .font(.title)
            .modifier(ListSectionFontModifier())) {
                
                Link(destination: StylesView().trackView(name: "Styles"),
                     label: "Styles")
            }
            .listRowBackground(Color(sectionColor, bundle: .module))

    }
    
    var popovers: some View {
        Section(header: Text("Popovers, alerts and sheets")
            .font(.title)
            .modifier(ListSectionFontModifier())) {
                
//                Link(destination: PopoversComponentView(),
//                     label: "Popovers")
                Link(destination: SheetsView().trackView(name: "Sheets"),
                     label: "Sheets")
//                Link(destination: AlertsComponentView(),
//                     label: "Alerts")
//                Link(destination: TimelineViews(),
//                     label: "Timelines")
//                Link(destination: SpacersDividersView(),
//                     label: "Spacer")
            }
            .listRowBackground(Color(sectionColor, bundle: .module))

    }
    
    var composedComponents: some View {
        Section(header: Text("Composed components to help speed up development")
            .font(.title)
            .modifier(ListSectionFontModifier())) {
                Link(destination: CommonlyUsedViews().trackView(name: "Commonly used views"),
                     label: "Commonly used views")
                Link(destination: CollectionsViews().trackView(name: "Collections of components"),
                       label: "Collections of components")
                Link(destination: StackedCardsView<CardView>(elementsCount: 22).trackView(name: "Stacked cards with dragging"),
                     label: "Stacked cards with dragging")
                Link(destination: InterfacingWithUIKitView(pages: ModelData().features.map { FeatureCardView(landmark: $0) }).trackView(name: "UIKit Interface"),
                     label: "UIKit Interface")
            }
            .listRowBackground(Color(sectionColor, bundle: .module))
        // end of composed VIEWS
        
    }
    
}


// MARK: - preview

#Preview {
    
        Group {
            ContentView()
                .preferredColorScheme(.dark)
        }
}
