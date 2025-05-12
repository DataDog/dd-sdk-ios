//
//  ChartsViews.swift
//  SwiftUICatalog
//
//  Created by Barbara Rodeker on 2023-02-05.
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
import Charts

struct ChartsViews: View {
    
    /// value used to draw a line chart example. It represents the initial time of a heart rate check.
    private let initialHour = 9
    /// value used to draw a line chart example. It represents the final time of a heart rate check.
    private let finalHour = 14
    /// x AXIS custom values, used to tailor the way in which the X axis of a line chart shows up
    private var xValuesHours: [Int] {
        stride(from: initialHour, to: finalHour, by: 1).map { $0 }
    }
    
    // MARK: - Bar chart example data
    
    /// For the bar chart, we will use clothes as examples, there are clothes of different colors. The colors will help to pile up bars for each type of item.
    private struct ClotheItem: Identifiable {
        var id = UUID()
        var type: String
        var color: String
        var count: Double
    }
    
    private let clothes: [ClotheItem] = [
        .init(type: "T-Shirt", color: "Pink", count: 4),
        .init(type: "T-Shirt", color: "Green", count: 5),
        .init(type: "Trouser", color: "Yellow", count: 5),
        .init(type: "Trouser", color: "Black", count: 49),
        .init(type: "Skirt", color: "Yellow", count: 4),
        .init(type: "Skirt", color: "Green", count: 9)
    ]
    
    // MARK: - Point Chart example data
    
    /// For the points chart we will use appliances which are stored in different rooms and we will plot the amount of appliances per storage unit/room
    private struct Appliance: Identifiable {
        var id = UUID()
        var type: String
        var code: Int
        var count: Double
        var storageUnit: String
    }
    
    private let appliances: [Appliance] = [
        Appliance(type: "Mixer", code: 1, count: 2, storageUnit: "Room1"),
        Appliance(type: "Mixer", code: 1, count: 4, storageUnit: "Room2"),
        Appliance(type: "Mixer", code: 1, count: 12, storageUnit: "Room3"),
        Appliance(type: "Microwave", code: 2, count: 20, storageUnit: "Room1"),
        Appliance(type: "Microwave", code: 2, count: 7, storageUnit: "Room2"),
        Appliance(type: "Microwave", code: 2, count: 1, storageUnit: "Room3"),
        Appliance(type: "Washing Machine", code: 3, count: 7, storageUnit: "Room1"),
        Appliance(type: "Washing Machine", code: 3, count: 2, storageUnit: "Room2"),
        Appliance(type: "Washing Machine", code: 3, count: 10, storageUnit: "Room3")
    ]
    
    // MARK: - Line Chart example data
    
    /// for the line chart example we will pretend to be in a clinical study where 3 persons' hearts rate are measures from 10:00h to 14:00h
    private struct HeartRate: Identifiable {
        var id = UUID()
        let hour: Int
        let heartRate: Double
        let personName: String
    }
    
    private let rates: [HeartRate] = [
        HeartRate(hour: 10, heartRate: 90.0, personName: "Mary"),
        HeartRate(hour: 11, heartRate: 87.0, personName: "Mary"),
        HeartRate(hour: 12, heartRate: 78.0, personName: "Mary"),
        HeartRate(hour: 13, heartRate: 93.0, personName: "Mary"),
        HeartRate(hour: 10, heartRate: 76.0, personName: "Laura"),
        HeartRate(hour: 11, heartRate: 78.0, personName: "Laura"),
        HeartRate(hour: 12, heartRate: 78.0, personName: "Laura"),
        HeartRate(hour: 13, heartRate: 70.0, personName: "Laura"),
        HeartRate(hour: 10, heartRate: 100.0, personName: "Mark"),
        HeartRate(hour: 11, heartRate: 110.0, personName: "Mark"),
        HeartRate(hour: 12, heartRate: 105.0, personName: "Mark"),
        HeartRate(hour: 13, heartRate: 95.0, personName: "Mark")
    ]
    
    
    // MARK: - Main view
    
    
    var body: some View {
        PageContainer(content:
                        VStack(alignment: .leading) {
            
            DocumentationLinkView(link: "https://developer.apple.com/documentation/charts/creating-a-chart-using-swift-charts", name: "CHARTS")
            
            Text("Since iOS16 Swift offers Swift Charts, there are different types of charts supported, we show many of them in the following examples.")
                .fontWeight(.light)
                .font(.title2)
                .padding(.bottom)
            
            // BAR CHART
            GroupBox {
                Text("Bar Chart example")
                    .fontWeight(.heavy)
                    .font(.title)
                Chart {
                    ForEach(clothes) { item in
                        BarMark(
                            x: .value("Item", item.type),
                            y: .value("Total Count", item.count)
                        )
                        .foregroundStyle(by: .value("Color", item.color))
                    }
                }
                .chartForegroundStyleScale([
                    "Green": .green,
                    "Black": .black,
                    "Pink": .pink,
                    "Yellow": .yellow
                ])
                .padding()
            }
            .modifier(Divided())
            
            GroupBox {
                // POINT CHART
                Text("Point Chart examples")
                    .fontWeight(.heavy)
                    .font(.title)
                Chart {
                    ForEach(appliances) {
                        PointMark(x: .value("Appliance Type", $0.type),
                                  y: .value("count", $0.count))
                        .foregroundStyle(by: .value("Storage Unit", $0.storageUnit))
                    }
                }
                .padding()
                Chart {
                    ForEach(appliances) {
                        PointMark(x: .value("Appliance Type", $0.type),
                                  y: .value("count", $0.count))
                        .symbol(by: .value("Storage Unit", $0.storageUnit))
                    }
                }
                .padding()
            }
            .modifier(Divided())
            GroupBox {
                // LINE CHART
                Text("Line Chart example")
                    .fontWeight(.heavy)
                    .font(.title)
                Chart {
                    ForEach(rates) {
                        LineMark(
                            x: .value("Hour", $0.hour),
                            y: .value("Value", $0.heartRate)
                        )
                        .foregroundStyle(by: .value("Name", $0.personName))
                    }
                }
                // This is one way to define a custom range for an axis
                .chartXScale(domain: ClosedRange(uncheckedBounds: (lower: 9, upper: 14)))
                // and this is how to set the labels for the custom defined axis
                .chartXAxis {
                    AxisMarks(values: xValuesHours)
                }
                .padding()
            }
            
            ContributedByView(name: "Barbara Martina",
                              link: "https://github.com/barbaramartina")
            .padding(.top, 80)
            
        }
        )
    }
}

#Preview {
    
        ChartsViews()
    
}
