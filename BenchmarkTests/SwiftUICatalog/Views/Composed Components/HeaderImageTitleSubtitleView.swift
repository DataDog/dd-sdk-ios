//
//  HeaderImageTitleSubtitle.swift
//  SwiftUICatalog
//
//  Created by Barbara Rodeker on 06.02.22.
//

import SwiftUI

struct HeaderImageTitleSubtitle: View, Identifiable {
    
    let id: String = "HeaderImageTitleSubtitle"
    
    struct Configuration {
        let title: String
        let titleFont: Font
        let titleWeight: Font.Weight
        let subtitle: String
        let subtitleFont: Font
        let subtitleWeight: Font.Weight
        let header: String
        let paddingTop: CGFloat
        let paddingLeading: CGFloat
        let paddingTrailing: CGFloat
        let paddingBottom: CGFloat
    }
    @State var configuration: Configuration
    
    var body: some View {
        
        VStack {
            
            Image(systemName: configuration.header)
                .resizable()
                .scaledToFit()
            
            Text(configuration.title)
                .font(configuration.titleFont)
                .fontWeight(configuration.titleWeight)
                .padding(.top, 16)
            
            Text(configuration.subtitle)
                .font(configuration.subtitleFont)
                .fontWeight(configuration.subtitleWeight)
                .padding(.top, 16)
            
            Rectangle()
                .fill(Color.gray)
                .frame(width: nil,
                       height: 1,
                       alignment: .center)
                .padding(.top, 12)
            
            
        }
        .padding(.top, configuration.paddingTop)
        .padding(.bottom, configuration.paddingBottom)
        .padding(.leading, configuration.paddingLeading)
        .padding(.trailing, configuration.paddingTrailing)
        
    }
}

#Preview {
    
        HeaderImageTitleSubtitle(configuration: HeaderImageTitleSubtitle.Configuration(title: "Snow flakes",
                                                                                       titleFont: .title,
                                                                                       titleWeight: .bold,
                                                                                       subtitle: "Snow comprises individual ice crystals that grow while suspended in the atmosphere—usually within clouds—and then fall",
                                                                                       subtitleFont: .body,
                                                                                       subtitleWeight: .regular,
                                                                                       header: "snowflake",
                                                                                       paddingTop: 16,
                                                                                       paddingLeading: 16,
                                                                                       paddingTrailing: 16,
                                                                                       paddingBottom: 16))
}
