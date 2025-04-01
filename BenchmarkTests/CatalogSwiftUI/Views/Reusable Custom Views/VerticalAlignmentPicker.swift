//
//  VerticalAlignmentPicker.swift
//  SwiftUICatalog
//
//  Created by Barbara Rodeker on 2024-03-30.
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

import Foundation
import SwiftUI

struct VerticalAlignmentPicker: View {
    
    @Binding var selection: VerticalAlignment
    
    /// alignments for stack view elements
    private let verticalAlignments: [VerticalAlignment] = [.top, .bottom, .center, .firstTextBaseline, .lastTextBaseline]
    
    var body: some View {
        Picker(selection: $selection, label: Text("alignment")) {
            ForEach(verticalAlignments, id: \.self) {
                Text($0.description)
            }
        }
    }
}
