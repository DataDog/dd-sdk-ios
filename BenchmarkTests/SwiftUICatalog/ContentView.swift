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

    private let monitor: DatadogMonitor

    public init(monitor: DatadogMonitor) {
        self.monitor = monitor

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
                .modifier(monitor.viewModifier(name: "SwiftUI Catalog"))
            }
            
        }
        // end of navigationview
    }
    
    // MARK: - Header sections
    
    private var topHeaderRow: some View {
        Group {
            Text("A catalog of components, controls, effects, styles and accessibility elements you can use to develop SwiftUI Interfaces in iOS and iPadOS.")
                .font(.footnote)
                .fontWeight(.light)
                .font(.title2)
                .padding(.top, 24)
                .padding(.bottom, 16)
                .foregroundColor(.white)
            
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
                    Link(destination: ButtonsComponentsView().modifier(monitor.viewModifier(name: "Buttons")),
                         label: "Buttons")
                    Link(destination: ImagesComponentView().modifier(monitor.viewModifier(name: "Images")),
                         label: "Images")
                    Link(destination: TextsComponentsView().modifier(monitor.viewModifier(name: "Texts")),
                         label: "Texts")
                    Link(destination: LabelsView().modifier(monitor.viewModifier(name: "Labels")),
                         label: "Labels")
                    Link(destination: MenusComponentView().modifier(monitor.viewModifier(name: "Menus")),
                         label: "Menus")
                }
                Group {
                    Link(destination: TogglesView().modifier(monitor.viewModifier(name: "Toggles")),
                         label: "Toggles")
                    Link(destination: SlidersView().modifier(monitor.viewModifier(name: "Sliders")),
                         label: "Sliders")
                    Link(destination: SteppersView().modifier(monitor.viewModifier(name: "Steppers")),
                         label: "Steppers")
                    Link(destination: PickersView().modifier(monitor.viewModifier(name: "Pickers")),
                         label: "Pickers")
                    Link(destination: DatePickersView().modifier(monitor.viewModifier(name: "Date Pickers")),
                         label: "Date Pickers")
                    Link(destination: ColorPickersView().modifier(monitor.viewModifier(name: "Color Pickers")),
                         label: "Color Pickers")
                    Link(destination: ProgressViews().modifier(monitor.viewModifier(name: "Progress View")),
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
                         label: "Consumable Product View").modifier(monitor.viewModifier(name: "Consumable Product View"))
                }
            }
            .listRowBackground(Color(sectionColor, bundle: .module))

    }
    
    var layouts: some View {
        Section(header: Text("Layouts")
            .font(.title)
            .modifier(ListSectionFontModifier())) {
                Link(destination: ListsComponentView().modifier(monitor.viewModifier(name: "Lists")),
                     label: "Lists")
                Link(destination: StacksView().modifier(monitor.viewModifier(name: "Stacks")),
                     label: "Stacks")
                Link(destination: GridsView().modifier(monitor.viewModifier(name: "Grids")),
                     label: "Grids")
                Link(destination: ContainersView().modifier(monitor.viewModifier(name: "Containers")),
                     label: "Containers")
                Link(destination: ScrollViewsView().modifier(monitor.viewModifier(name: "Scrollviews")),
                     label: "Scrollviews")
                Link(destination: TableViews().modifier(monitor.viewModifier(name: "Table Views")),
                     label: "Table Views")
            }
            .listRowBackground(Color(sectionColor, bundle: .module))
    }
    
    var hierachicalViews: some View {
        Section(header: Text("Hierachical Views")               .font(.title)
            .modifier(ListSectionFontModifier())) {
                Link(destination: NavigationBarsComponentView().modifier(monitor.viewModifier(name: "Navigation")),
                     label: "Navigation")
                Link(destination: OutlinesGroupsView().modifier(monitor.viewModifier(name: "Outlines")),
                     label: "Outlines")
                Link(destination: DisclosureGroupsView().modifier(monitor.viewModifier(name: "Disclosures")),
                     label: "Disclosures")
                Link(destination: TabsView().modifier(monitor.viewModifier(name: "Tabs")),
                     label: "Tabs")
            }
            .listRowBackground(Color(sectionColor, bundle: .module))

    }
    
    var drawings: some View {
        Section(header: Text("Drawing and animations")
            .font(.title)
            .modifier(ListSectionFontModifier())) {
                Link(destination: CanvasView().modifier(monitor.viewModifier(name: "Canvas")),
                     label: "Canvas")
                Link(destination: GraphicContextsView().modifier(monitor.viewModifier(name: "Graphic Context")),
                     label: "Graphic Context")
                Link(destination: ShapesView().modifier(monitor.viewModifier(name: "Shapes")),
                     label: "Shapes")
                Link(destination: AnimationsView().modifier(monitor.viewModifier(name: "Animations")),
                     label: "Animations")
                Link(destination: GeometriesView().modifier(monitor.viewModifier(name: "Geometries")),
                     label: "Geometries")
            }
            .listRowBackground(Color(sectionColor, bundle: .module))

    }

    @available(iOS 16.0, tvOS 16.0, *)
    var charts: some View {
        Section(header: Text("Charts")
            .font(.title)
            .modifier(ListSectionFontModifier())) {
                Link(destination: ChartsViews().modifier(monitor.viewModifier(name: "Swift Charts")),
                     label: "Swift Charts")
            }
            .listRowBackground(Color(sectionColor, bundle: .module))

    }
    
    var gestures: some View {
        Section(header: Text("Gestures")
            .font(.title)
            .modifier(ListSectionFontModifier())) {
                Link(destination: GesturesView().modifier(monitor.viewModifier(name: "Gestures")),
                     label: "Gestures")
                Link(destination: ComposingGesturesView().modifier(monitor.viewModifier(name: "Composing Gestures")),
                     label: "Composing Gestures")
                Link(destination: SensoryFeedbackInViews().modifier(monitor.viewModifier(name: "Sensory Feedback")),
                     label: "Sensory Feedback")
            }
            .listRowBackground(Color(sectionColor, bundle: .module))

    }
    
    var viewModifiers: some View {
        Section(header: Text("View modifiers")
            .font(.title)
            .modifier(ListSectionFontModifier())) {
                Link(destination: TextModifiersView().modifier(monitor.viewModifier(name: "Text modifiers")),
                     label: "Text modifiers")
                Link(destination: EffectsModifiersView().modifier(monitor.viewModifier(name: "Effect modifiers")),
                     label: "Effect modifiers")
                Link(destination: LayoutModifiersView().modifier(monitor.viewModifier(name: "Layout modifiers")),
                     label: "Layout modifiers")
                
            }
            .listRowBackground(Color(sectionColor, bundle: .module))

    }
    
    var accessibility: some View {
        Section(header: Text("Accesibility")
            .font(.title)
            .modifier(ListSectionFontModifier())) {
                
                Link(destination: AccesibilityView().modifier(monitor.viewModifier(name: "Accesibility")),
                     label: "Accesibility")
            }
            .listRowBackground(Color(sectionColor, bundle: .module))

    }
    
    var statusBars: some View {
        Section(header: Text("Status and tool bars")
            .font(.title)
            .modifier(ListSectionFontModifier())) {
                Link(destination: ToolbarsComponentView().modifier(monitor.viewModifier(name: "Tool Bars")),
                     label: "Tool Bars")
            }
            .listRowBackground(Color(sectionColor, bundle: .module))

    }
    
    var stylingSection: some View {
        Section(header: Text("Styling")
            .font(.title)
            .modifier(ListSectionFontModifier())) {
                
                Link(destination: StylesView().modifier(monitor.viewModifier(name: "Styles")),
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
                Link(destination: SheetsView().modifier(monitor.viewModifier(name: "Sheets")),
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
                Link(destination: CommonlyUsedViews().modifier(monitor.viewModifier(name: "Commonly used views")),
                     label: "Commonly used views")
                Link(destination: CollectionsViews().modifier(monitor.viewModifier(name: "Collections of components")),
                       label: "Collections of components")
                Link(destination: StackedCardsView<CardView>(elementsCount: 22).modifier(monitor.viewModifier(name: "Stacked cards with dragging")),
                     label: "Stacked cards with dragging")
                Link(destination: InterfacingWithUIKitView(pages: ModelData().features.map { FeatureCardView(landmark: $0) }).modifier(monitor.viewModifier(name: "UIKit Interface")),
                     label: "UIKit Interface")
            }
            .listRowBackground(Color(sectionColor, bundle: .module))
        // end of composed VIEWS
        
    }
    
}


// MARK: - preview

#Preview {
    
        Group {
            ContentView(monitor: NOPDatadogMonitor())
                .preferredColorScheme(.dark)
        }
}
