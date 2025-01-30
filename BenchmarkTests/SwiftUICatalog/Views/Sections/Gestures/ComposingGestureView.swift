//
//  ComposingGesturesView.swift
//  SwiftUICatalog
//
// MIT License
//
// Copyright (c) 2021 Ali Ghayeni H
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
/// Examples on how to use  GESTURES  in SwiftUI
/// OFFICIAL DOCUMENTATION:
/// https://developer.apple.com/documentation/swiftui/adding-interactivity-with-gestures
/// https://developer.apple.com/documentation/swiftui/composing-swiftui-gestures
///
///

struct ComposingGesturesView: View, Comparable {
    
    let id: String = "ComposingGesturesView"
    
    enum DragState: Equatable {
        case inactive
        case pressing
        case dragging(translation: CGSize)
        
        var translation: CGSize {
            switch self {
            case .inactive, .pressing:
                return .zero
            case .dragging(let translation):
                return translation
            }
        }
        
        var isActive: Bool {
            switch self {
            case .inactive:
                return false
            case .pressing, .dragging:
                return true
            }
        }
        
        var isDragging: Bool {
            switch self {
            case .inactive, .pressing:
                return false
            case .dragging:
                return true
            }
        }
    }
    
    @GestureState private var dragState = DragState.inactive
    @State private var viewState = CGSize.zero
    private let minimumLongPressDuration = 0.5
    
    var body: some View {
        
        
        let longPressDrag = LongPressGesture(minimumDuration: minimumLongPressDuration)
            .sequenced(before: DragGesture())
            .updating($dragState) { value, state, transaction in
                switch value {
                    // Long press begins.
                case .first(true):
                    state = .pressing
                    // Long press confirmed, dragging may begin.
                case .second(true, let drag):
                    state = .dragging(translation: drag?.translation ?? .zero)
                    // Dragging ended or the long press cancelled.
                default:
                    state = .inactive
                }
            }
            .onEnded { value in
                guard case .second(true, let drag?) = value else { return }
                self.viewState.width += drag.translation.width
                self.viewState.height += drag.translation.height
            }
        
        VStack(alignment: .leading) {
            DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/adding-interactivity-with-gestures", name: "GESTURES")
            
            Text("Try to click and hold your finger, then drag the circle and enjoy this gesture in SwiftUI.")
                .fontWeight(.light)
                .font(.title2)
            Text("Offset = x: \(viewState.width + dragState.translation.width) - y: \(viewState.height + dragState.translation.height)")
            Circle()
                .fill(Color.blue)
                .overlay(dragState.isDragging ? Circle().stroke(Color.white, lineWidth: 2) : nil)
                .frame(width: 100, height: 100, alignment: .center)
                .offset(
                    x: viewState.width + dragState.translation.width,
                    y: viewState.height + dragState.translation.height
                )
                .animation(.easeInOut, value: dragState)
                .shadow(radius: dragState.isActive ? 8 : 0)
                .animation(.linear(duration: minimumLongPressDuration), value: dragState)
                .gesture(longPressDrag)
            
            Spacer()
            ContributedByView(name: "Ali Ghayeni H",
                              link: "https://github.com/alighayeni")
            .padding(.top, 80)
            
        }
        .padding(.horizontal)
        
        // end of page container
        
    }
    
}

#Preview {
    
        ComposingGesturesView()
    
}

// MARK: - HASHABLE

extension ComposingGesturesView {
    
    static func == (lhs: ComposingGesturesView, rhs: ComposingGesturesView) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}


