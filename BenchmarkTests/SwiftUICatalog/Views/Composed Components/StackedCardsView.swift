//
//  StackedCardsView.swift
//  Catalog
//
//  Created by Barbara Personal on 2024-11-24.
//
// MIT License
//
// Copyright (c) 2024 Barbara Rodeker
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

// MARK: - IndexedView

/// a simple protocol to represent a view which needs to know in
/// which index it is, to be able to create itself
protocol IndexedView: View {
    init(index: Int)
}

/// a container in a Zstack of cards
/// when displaying them, it gives them an horizontal and vertical offet
struct StackedCardsView<T: IndexedView>: View {
    /// how many cards could be created
    private let elementsCount: Int
    /// just an array of offset to overlay one card on top of each other and
    /// be able to see the cards which are behind
    private var offsets: [CGFloat] = [10, 20, 30, 40]

    
    init(elementsCount: Int) {
        self.elementsCount = elementsCount
    }
    
    // MARK: - body
    
    var body: some View {
        ZStack {
            ForEach(0..<elementsCount) { index in
                T(index: index)
                    .offset(CGSize(width: offsets[index % offsets.count],
                                   height: offsets[index % offsets.count]))
            }
        }
    }
}

// MARK: - CardView an example of an IndexedView

struct CardView: IndexedView {
    
    /// the index of the card
    private let index: Int
    /// dragging related/view state
    @State private var viewState = CGSize.zero
    /// gesture state, it is updated when the finger is long pressing - moves - is released
    @GestureState private var dragState = DragState.inactive
    /// initially to activate the drag in a card, you need to press and hold for this amount of time
    private let minimumLongPressDuration = 0.5
    
    /// to track the finger movements and interactions
    private enum DragState: Equatable {
        /// no finger on top of the card
        case inactive
        /// finger pressing
        case pressing
        /// finger already pressed-hold and now is moving
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
    
    // MARK: - Initializer
    
    init(index: Int) {
        self.index = index
    }
    
    // MARK: - Body

    var body: some View {
        
        // we create a long press gesture for the card
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

        // now create the card vertical stack and connect to the gesture
        VStack {
            Text("\(index)")
                .fontWeight(.heavy)
                .font(.largeTitle)
        }
        .frame(width: 250, height: 400)
        .background([.cyan, .mint, .blue, .pink, .green, .gray, .yellow].randomElement()!)
        .cornerRadius(8)
        .overlay(content: {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.black,
                        lineWidth: 2)
        })
        .offset(
            x: viewState.width + dragState.translation.width,
            y: viewState.height + dragState.translation.height
        )
        .animation(.easeInOut, value: dragState)
        .shadow(radius: dragState.isActive ? 8 : 0)
        .animation(.linear(duration: minimumLongPressDuration), value: dragState)
        .gesture(longPressDrag)
    }
}

// MARK: - PREVIEWS

#Preview {
    StackedCardsView<CardView>(elementsCount: 30)
}
