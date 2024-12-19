//
//  TitleSubtitleIconView.swift
//  SwiftUICatalog
//
//  Created by Barbara Rodeker on 06.02.22.
//

import SwiftUI

///
/// A view commonly used includes a title, a longer description and an icon.
/// This view allows to create this combination of items easily.
///
///  TITLE                                              (ICON)
///  LONGER DESCRIPTION
///
///  The ICON vertical and horizontal alignments can be configured.
///  As well as the font, weight and paddings of the view.
///
struct TitleSubtitleIconView: View, Identifiable {
    
    let id = UUID()
    
    struct Configuration {
        let backgroundColor: Color
        let title: String
        let titleFont: Font
        let titleWeight: Font.Weight
        let subtitle: String
        let subtitleFont: Font
        let subtitleWeight: Font.Weight
        let icon: String
        let iconSize: CGSize
        let iconVerticalAlignment: VerticalAlignment
        let iconHorizontalAlignment: HorizontalAlignment
        let paddingTop: CGFloat
        let paddingLeading: CGFloat
        let paddingTrailing: CGFloat
        let paddingBottom: CGFloat
    }
    @State var configuration: Configuration
    
    var body: some View {
        
        VStack(alignment: .center) {
            HStack(alignment: configuration.iconVerticalAlignment) {
                
                if configuration.iconHorizontalAlignment == .leading {
                    Image(systemName: configuration.icon)
                        .resizable()
                        .scaledToFit()
                        .padding(.top)
                        .frame(width: configuration.iconSize.width, height: configuration.iconSize.height)
                    
                }
                
                VStack(alignment: configuration.iconHorizontalAlignment == .center ? .center : .leading) {
                    
                    if configuration.iconHorizontalAlignment == .center {
                        Image(systemName: configuration.icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: configuration.iconSize.width, height: configuration.iconSize.height,
                                   alignment: .center)
                        
                    }
                    
                    Text(configuration.title)
                        .font(configuration.titleFont)
                        .fontWeight(configuration.titleWeight)
                        .padding(.top, 16)
                    
                    Text(configuration.subtitle)
                        .font(configuration.subtitleFont)
                        .fontWeight(configuration.subtitleWeight)
                        .padding(.top, 16)
                }
                
                if configuration.iconHorizontalAlignment == .trailing {
                    Image(systemName: configuration.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: configuration.iconSize.width, height: configuration.iconSize.height)
                    
                }
                
            }
            Rectangle()
                .fill(Color.gray)
                .frame(width: nil,
                       height: 1,
                       alignment: .center)
                .padding(.top, 12)
            
        }
        .background(configuration.backgroundColor)
        .padding(.top, configuration.paddingTop)
        .padding(.bottom, configuration.paddingBottom)
        .padding(.leading, configuration.paddingLeading)
        .padding(.trailing, configuration.paddingTrailing)
        
    }
    
}

#Preview {
    
    
        TitleSubtitleIconView(configuration:  TitleSubtitleIconView.Configuration(backgroundColor: Color.brown, title: "Sun"
                                                                                  , titleFont: .title,
                                                                                  titleWeight: .bold,
                                                                                  subtitle: "The Sun is the star at the heart of our solar system. Its gravity holds the solar system together, keeping everything – from the biggest planets to the smallest"
                                                                                  , subtitleFont: .body,
                                                                                  subtitleWeight: .regular,
                                                                                  icon: "sun.max", iconSize: CGSize(width: 60, height: 60),
                                                                                  iconVerticalAlignment: .center, iconHorizontalAlignment: .leading
                                                                                  ,
                                                                                  paddingTop: 16,
                                                                                  paddingLeading: 16,
                                                                                  paddingTrailing: 16,
                                                                                  paddingBottom: 16)
        )
    
}
