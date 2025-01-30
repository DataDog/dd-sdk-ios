//
//  PageContainer.swift
//  SwiftUICatalog
//
//  Created by Barbara Rodeker on 2022-05-21.
//

import SwiftUI

struct PageContainer<Content>: View where Content: View {
    
    let content: Content
    
    var body: some View {
        ZStack {
            Color("PageContainerColor", bundle: .module)
                .ignoresSafeArea()
            
            ScrollView {
                content
            }
            .padding(.vertical, Style.VerticalPadding.medium.rawValue)
            .padding(.horizontal, Style.HorizontalPadding.medium.rawValue)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color("Medium", bundle: .module), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

#Preview {
    
        PageContainer(content: Text("Content"))
    }

