//
//  CommonlyUsedViews.swift
//  SwiftUICatalog
//
//  Created by Barbara Rodeker on 06.02.22.
//

import SwiftUI

struct CommonlyUsedViews: View, Comparable {
    
    let id: String = "CommonlyUsedViews"
    
    var body: some View {
        
        ScrollView {
            
            example1
            example2
            example3
            
        }
        
        
    }
    
    // MARK: - Example Views
    
    // Big header - title - description view
    private var example1: some View {
        
        GroupBox {
            
            Text("A view with an image as header, a title and a longer text below")
                .fontWeight(.heavy)
                .font(.title)
            
                .padding(.top, 12)
            Text("You can combine a set of those in an array and iterate to create a collection layout. Padding, fonts and content are configurable.")
                .fontWeight(.light)
                .font(.title2)
            
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
        .padding()
        
    }
    
    // Card with icons - title - description
    private var example2: some View {
        GroupBox {
            Text("A view with an icon, a title and a longer text below")
                .fontWeight(.heavy)
                .font(.title)
            
                .padding(.top, 12)
            Text("The size of the icon and the horizontal and vertical alignment can be configured.")
                .fontWeight(.light)
                .font(.title2)
            
            let configurationIcon1 = iconConfiguration(with: Color.pink,
                                                       title: snowTitle,
                                                       subtitle: snowDescription,
                                                       iconName: snowIcon)
            
            TitleSubtitleIconView(configuration: configurationIcon1)
            
            let configurationIcon2 = iconConfiguration(with: Color.gray,
                                                       title: sunTitle,
                                                       subtitle: sunDescription,
                                                       iconName: sunIcon)
            
            TitleSubtitleIconView(configuration: configurationIcon2)
            
            let configurationIcon3 = iconConfiguration(with: Color.green,
                                                       title: rainTitle,
                                                       subtitle: rainDescription,
                                                       iconName: rainIcon)
            
            TitleSubtitleIconView(configuration: configurationIcon3)
            
        }
        .padding()
    }
    
    private func iconConfiguration(with color: Color, title: String, subtitle: String, iconName: String) -> TitleSubtitleIconView.Configuration {
        TitleSubtitleIconView.Configuration(backgroundColor: color,
                                            title: title,
                                            titleFont: .title,
                                            titleWeight: .bold,
                                            subtitle: subtitle,
                                            subtitleFont: .body,
                                            subtitleWeight: .regular,
                                            icon: iconName,
                                            iconSize: CGSize(width: 60, height: 60),
                                            iconVerticalAlignment: .top,
                                            iconHorizontalAlignment: .center,
                                            paddingTop: 16,
                                            paddingLeading: 16,
                                            paddingTrailing: 16,
                                            paddingBottom: 16)
    }
    
    // swipable view
    private var example3: some View {
        GroupBox {
            
            let configurationIcon1 = iconConfiguration(with: Color.pink,
                                                       title: snowTitle,
                                                       subtitle: snowDescription,
                                                       iconName: snowIcon)
            
            let configurationIcon2 = iconConfiguration(with: Color.blue,
                                                       title: sunTitle,
                                                       subtitle: sunDescription,
                                                       iconName: sunIcon)
            
            
            SwipableViewContainer(subviews: [TitleSubtitleIconView(configuration: configurationIcon2),
                                             TitleSubtitleIconView(configuration: configurationIcon1)])
        }
    }
    
    // MARK: - Auxiliar variables for titles and descriptions of dogs.
    // In a real production application these vars will fit better in a view model
    // but this catalog is only focused on showing UI in SwiftUI, not in architecture or data organization
    
    private var snowIcon: String {
        "snowflake"
    }
    
    private var snowTitle: String {
        "snowflake.circle.fill"
    }
    
    private var snowDescription: String {
        "Snow comprises individual ice crystals that grow while suspended in the atmosphere—usually within clouds"
    }
    
    private var sunIcon: String {
        "sun.max"
    }
    
    private var sunTitle: String {
        "Sun"
    }
    
    private var sunDescription: String {
        "The Sun is the star at the heart of our solar system. Its gravity holds the solar system together, keeping everything – from the biggest planets to the smallest"
    }
    
    private var rainIcon: String {
        "cloud.bolt.rain"
    }
    
    private var rainTitle: String {
        "Rain"
    }
    
    private var rainDescription: String {
        "Rain is water droplets that have condensed from atmospheric water vapor and then fall under gravity. "
    }
    
}

#Preview {
    
        CommonlyUsedViews()
    
}

