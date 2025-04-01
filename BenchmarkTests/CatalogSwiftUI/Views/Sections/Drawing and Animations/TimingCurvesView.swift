//
//  TimingCurvesView.swift
//  Catalog
//
//  Created by Barbara Personal on 2024-05-28.
//

import SwiftUI

struct TimingCurvesView: View {
    @State private var isActive1 = false
    @State private var isActive2 = false
    @State private var isActive3 = false
    @State private var isActive4 = false
    @State private var isActive5 = false
    @State private var isActive6 = false
    @State private var isActive7 = false
    
    var body: some View {
        PageContainer(content:
                        
                        ScrollView {
            
            DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/animation/spring")
            
            VStack(alignment: .leading) {
                Text("Since iOS17 spring animations can be applied to views and easily created.")
                    .fontWeight(.light)
                    .font(.title2)
                example1
                    .modifier(Divided())
                example2
                    .modifier(Divided())
                example3
                    .modifier(Divided())
                example4
                    .modifier(Divided())
                example5
                    .modifier(Divided())
                example6
                    .modifier(Divided())
                example7
                    .modifier(Divided())
            }
            
        })
    }
    
    private var example7: some View {
        GroupBox {
            HStack {
                Text("Creates a new curve using bezier control points.")
                    .fontWeight(.light)
                    .font(.title2)
                Spacer()
            }
            Button(action: {
                withAnimation(.timingCurve(.bezier(startControlPoint: UnitPoint(x: 0, y: 0),
                                                   endControlPoint: UnitPoint(x: 0.5, y: 0.8)), duration: 4.0)) {
                    isActive7.toggle()
                }
            }, label: {
                Text("Bezier")
                    .modifier(ButtonFontModifier())
            })
            .frame(maxWidth: .infinity)
            .modifier(RoundedBordersModifier(radius: 10,
                                             lineWidth: 2))
            Circle()
                .frame(width: isActive7 ? 200.0 : 10.0)
                .foregroundColor(.accentColor)
        }
    }
    
    private var example1: some View {
        GroupBox {
            Text("A bezier curve that starts out slowly, then speeds up as it finishes.")
                .fontWeight(.light)
                .font(.title2)
            Button(action: {
                withAnimation(.timingCurve(.easeIn, duration: 4.0)) {
                    isActive1.toggle()
                }
            }, label: {
                Text("Ease In")
                    .modifier(ButtonFontModifier())
            })
            .frame(maxWidth: .infinity)
            .modifier(RoundedBordersModifier(radius: 10,
                                             lineWidth: 2))
            Circle()
                .frame(width: isActive1 ? 200.0 : 10.0)
                .foregroundColor(.accentColor)
        }
    }
    private var example2: some View {
        GroupBox {
            Text("A bezier curve that starts out quickly, then slows down as it approaches the end.")
                .fontWeight(.light)
                .font(.title2)
            Button(action: {
                withAnimation(.timingCurve(.easeOut, duration: 4.0)) {
                    isActive2.toggle()
                }
            }, label: {
                Text("Ease Out")
                    .modifier(ButtonFontModifier())
            })
            .frame(maxWidth: .infinity)
            .modifier(RoundedBordersModifier(radius: 10,
                                             lineWidth: 2))
            Circle()
                .frame(width: isActive2 ? 200.0 : 10.0)
                .foregroundColor(.accentColor)
        }
    }
    private var example3: some View {
        GroupBox {
            Text("A bezier curve that starts out slowly, speeds up over the middle, then slows down again as it approaches the end.")
                .fontWeight(.light)
                .font(.title2)
            Button(action: {
                withAnimation(.timingCurve(.easeInOut, duration: 4.0)) {
                    isActive3.toggle()
                }
            }, label: {
                Text("Ease In Out")
                    .modifier(ButtonFontModifier())
            })
            .frame(maxWidth: .infinity)
            .modifier(RoundedBordersModifier(radius: 10,
                                             lineWidth: 2))
            Circle()
                .frame(width: isActive3 ? 200.0 : 10.0)
                .foregroundColor(.accentColor)
        }
    }
    private var example4: some View {
        GroupBox {
            Text("A curve that starts out slowly, then speeds up as it finishes.")
                .fontWeight(.light)
                .font(.title2)
            Button(action: {
                withAnimation(.timingCurve(.circularEaseIn, duration: 4.0)) {
                    isActive4.toggle()
                }
            }, label: {
                Text("Circular Ease In")
                    .modifier(ButtonFontModifier())
            })
            .frame(maxWidth: .infinity)
            .modifier(RoundedBordersModifier(radius: 10,
                                             lineWidth: 2))
            Circle()
                .frame(width: isActive4 ? 200.0 : 10.0)
                .foregroundColor(.accentColor)
        }
    }
    private var example5: some View {
        GroupBox {
            Text("A curve that starts out slowly, then speeds up as it finishes.")
                .fontWeight(.light)
                .font(.title2)
            Button(action: {
                withAnimation(.timingCurve(.circularEaseOut, duration: 4.0)) {
                    isActive5.toggle()
                }
            }, label: {
                Text("Circular Ease Out")
                    .modifier(ButtonFontModifier())
            })
            .frame(maxWidth: .infinity)
            .modifier(RoundedBordersModifier(radius: 10,
                                             lineWidth: 2))
            Circle()
                .frame(width: isActive5 ? 200.0 : 10.0)
                .foregroundColor(.accentColor)
        }
    }
    private var example6: some View {
        GroupBox {
            Text("A curve that starts out slowly, then speeds up as it finishes.")
                .fontWeight(.light)
                .font(.title2)
            Button(action: {
                withAnimation(.timingCurve(.circularEaseInOut, duration: 4.0)) {
                    isActive6.toggle()
                }
            }, label: {
                Text("Circular Ease In Out")
                    .modifier(ButtonFontModifier())
            })
            .frame(maxWidth: .infinity)
            .modifier(RoundedBordersModifier(radius: 10,
                                             lineWidth: 2))
            Circle()
                .frame(width: isActive6 ? 200.0 : 10.0)
                .foregroundColor(.accentColor)
        }
    }
}

#Preview {
    TimingCurvesView()
}
