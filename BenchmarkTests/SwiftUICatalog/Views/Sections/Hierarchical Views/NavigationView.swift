//
//  NavigationBarsComponentView.swift
//  SwiftUICatalog
//
// MIT License
//
// Copyright (c) 2021 Barbara Martina
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
//

import SwiftUI

///
/// Example on how to set and configure a NavigationView in SwiftUI
/// OFFICIAL DOCUMENTATION https://developer.apple.com/documentation/swiftui/navigationstack
/// https://developer.apple.com/documentation/swiftui/navigationlink
///
struct NavigationBarsComponentView: View, Comparable {
    
    struct Reminder {
        let title: String
        let text: String
    }
    
    let id: String = "NavigationBarsComponentView"
    
    @State private var reminders: [Reminder] = [
        Reminder(title: "2021-10-21", text: "Pick up John from school"),
        Reminder(title: "Coffee", text: "we are running out of coffee"),
        Reminder(title: "Washing machine", text: "Call the handy man, the machine broke"),
        Reminder(title: "Hairdresser", text: "Johninstrasse 14, 09:00")
    ]
    
    var body: some View {
        
        NavigationStack {
            
            DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/navigationstack")
            
            List {
                NavigationLink(reminders[0].title,
                               destination: Text(reminders[0].text))
                NavigationLink(reminders[1].title,
                               destination: Text(reminders[1].text))
                NavigationLink(reminders[2].title,
                               destination: Text(reminders[2].text))
                NavigationLink(reminders[3].title,
                               destination: Text(reminders[3].text))
                
                
            }
            .navigationTitle("Reminders")
            // adjusting the navigation view style with these options: https://developer.apple.com/documentation/swiftui/navigationviewstyle
            .navigationViewStyle(DoubleColumnNavigationViewStyle())
            // end of list
            
            ContributedByView(name: "Barbara Martina",
                              link: "https://github.com/barbaramartina")
            .padding(.top, 80)
        }
        .padding(.horizontal, Style.HorizontalPadding.medium.rawValue)
        // end of navigation view
        
        
    }
}

#Preview {
    
        NavigationBarsComponentView()
}

// MARK: - HASHABLE

extension NavigationBarsComponentView {
    
    static func == (lhs: NavigationBarsComponentView, rhs: NavigationBarsComponentView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}


