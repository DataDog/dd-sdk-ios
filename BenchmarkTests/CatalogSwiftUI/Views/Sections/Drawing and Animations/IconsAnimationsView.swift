//
//  IconsAnimationsView.swift
//  Catalog
//
//  Created by Barbara Personal on 2024-06-01.
//

import SwiftUI

struct IconsAnimationsView: View {
    
    @State private var isActive1 = false
    @State private var isActive2 = false
    @State private var isActive3 = false
    @State private var isActive4 = false
    @State private var isActive5 = false
    @State private var isActive6 = false
    @State private var isActive7 = false
    @State private var isActive8 = false
    
    var body: some View {
        PageContainer(content:
                        
                        ScrollView {
            
            DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/animation")
            
            VStack(alignment: .leading) {
                Text("SwiftUI provides a wide range of animations which can be applied to some properties of the view elements, such as the scale, the opacity, the offset. It also provides a set of more complex animations. Here was have some examples of what is possible when it comes to using SwiftUI animations toolbox")
                    .fontWeight(.light)
                    .font(.title2)
                
                example8
                example7
                example6
                example5
                example4
                example1
                example2
                example3
            }
        })
    }
    
    private var example1: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("In this example, we have a button with an icon and we can play an animation when the offset of the image changes, combining it with a scale and rotation effect (press the icon to see it in action)")
                    .fontWeight(.light)
                    .font(.title2)
                HStack {
                    Button(action: {
                        isActive1.toggle()
                    }, label: {
                        Image(systemName: "play.circle")
                            .resizable()
                            .frame(width: 44, height: 44)
                    })
                    Spacer()
                    Image(systemName: "pencil.tip")
                        .resizable()
                        .rotationEffect(isActive1 ? Angle(degrees: 360) : Angle(degrees: 0))
                        .scaleEffect(isActive1 ? 1.2 : 1 )
                        .offset(x: isActive1 ? 10 : 0)
                        .animation(.easeInOut(duration: 0.6).repeatCount(3, autoreverses: true),
                                   value: isActive1)
                        .frame(width: 50, height: 60)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    private var example2: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("In this case we are using a scale effect on the image, combined with a bouncy spring animation. The animation is repeated 5 times which makes it feels like a heart beating")
                    .fontWeight(.light)
                    .font(.title2)
                HStack {
                    Button(action: {
                        isActive2.toggle()
                    }, label: {
                        Image(systemName: "play.circle")
                            .resizable()
                            .frame(width: 44, height: 44)
                    })
                    Spacer()
                    Image(systemName: "heart.fill")
                        .resizable()
                        .scaleEffect(isActive2 ? 1.2 : 1 )
                        .animation(.spring(.bouncy).repeatCount(5), value: isActive2)
                        .frame(width: 50, height: 50)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    private var example3: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("To catch users attention, we could also make an image rotate, when some event is triggered.")
                    .fontWeight(.light)
                    .font(.title2)
                HStack {
                    Button(action: {
                        isActive3.toggle()
                    }, label: {
                        Image(systemName: "play.circle")
                            .resizable()
                            .frame(width: 44, height: 44)
                    })
                    Spacer()
                    Image(systemName: "bonjour")
                        .resizable()
                        .rotationEffect(isActive3 ? .degrees(360) : .zero)
                        .animation(.easeInOut(duration: 1).repeatCount(10),
                                   value: isActive3)
                        .frame(width: 80, height: 80)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    private var example6: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("The corner radius of an element can change and we can also use an animation during the change, controlling the duration and repeating it adds a feeling of transformation to the element")
                    .fontWeight(.light)
                    .font(.title2)
                HStack {
                    Button(action: {
                        isActive6.toggle()
                    }, label: {
                        Image(systemName: "play.circle")
                            .resizable()
                            .frame(width: 44, height: 44)
                    })
                    Spacer()
                    RoundedRectangle(cornerRadius: isActive6 ? 18 : 0)
                        .animation(.easeIn(duration: 0.7).repeatCount(10), value: isActive6)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    private let gradient2 = LinearGradient(colors: [ .green, .blue, .white], startPoint: .zero, endPoint: .bottomTrailing)
    private let gradient1 = LinearGradient(colors: [ .white, .brown, .pink], startPoint: .zero, endPoint: .bottomTrailing)
    private var example7: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("A gradient can also change with an animation")
                    .fontWeight(.light)
                    .font(.title2)
                HStack {
                    Button(action: {
                        isActive7.toggle()
                    }, label: {
                        Image(systemName: "play.circle")
                            .resizable()
                            .frame(width: 44, height: 44)
                    })
                    Spacer()
                    Rectangle()
                        .fill(isActive7 ? gradient1 : gradient2)
                        .animation(.snappy, value: isActive7)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    private var example5: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("The shadow of an object can also be animated with different effects to make the object seems like if it is moving")
                    .fontWeight(.light)
                    .font(.title2)
                HStack {
                    Button(action: {
                        isActive5.toggle()
                    }, label: {
                        Image(systemName: "play.circle")
                            .resizable()
                            .frame(width: 44, height: 44)
                    })
                    Spacer()
                    Image(systemName: "figure.cooldown")
                        .resizable()
                        .shadow(color: isActive5 ? .green : .clear, radius: isActive5 ? /*@START_MENU_TOKEN@*/10/*@END_MENU_TOKEN@*/ : 0)
                        .animation(.easeInOut(duration: 1).repeatCount(5),
                                   value: isActive5)
                        .frame(width: 50, height: 75)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    private struct AnimatedProperties {
        var scale: CGFloat = 1
        var rotation: Angle = Angle(degrees: 0)
        var opacity: CGFloat = 1
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0
    }
    private var example8: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("Keyframe animator was introduced in iOS 17 and it allows to perform animations of several properties at the same time")
                    .fontWeight(.light)
                    .font(.title2)
                HStack {
                    Spacer()
                    Image(systemName: "figure.outdoor.cycle")
                        .resizable()
                        .frame(width: 60, height: 50)
                        .keyframeAnimator(initialValue: AnimatedProperties()) {
                            content, value in
                            
                            content
                                .scaleEffect(value.scale)
                                .offset(x: value.offsetX, y: value.offsetY)
                                .opacity(value.opacity)
                                .rotationEffect(value.rotation)
                            
                        } keyframes: { _ in
                            
                            KeyframeTrack(\.scale) {
                                CubicKeyframe(0.8, duration: 0.2)
                                CubicKeyframe(1.6, duration: 0.1)
                                CubicKeyframe(0.4, duration: 0.3)
                                CubicKeyframe(0.8, duration: 0.2)
                            }
                            
                            KeyframeTrack(\.offsetX) {
                                SpringKeyframe(1.5, duration: 0.4)
                                SpringKeyframe(0.9, duration: 2)
                                SpringKeyframe(51.9, duration: 0.4)
                                SpringKeyframe(1.0, duration: 0.4)
                                SpringKeyframe(-50.2, duration: 0.4)
                            }
                            
                            KeyframeTrack(\.offsetY) {
                                SpringKeyframe(0.2, duration: 0.4)
                                SpringKeyframe(10.5, duration: 2)
                                SpringKeyframe(1.5, duration: 0.4)
                                SpringKeyframe(1.0, duration: 0.4)
                                SpringKeyframe(1.9, duration: 0.4)
                            }
                            
                            KeyframeTrack(\.opacity) {
                                LinearKeyframe(0.3, duration: 0.2)
                                LinearKeyframe(1.0, duration: 0.3)
                                LinearKeyframe(0.9, duration: 0.2)
                                LinearKeyframe(0.6, duration: 0.33)
                                LinearKeyframe(0.8, duration: 0.2)
                            }
                        }
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    private var example4: some View {
        GroupBox {
            GeometryReader { geometry in
                VStack(alignment: .leading) {
                    Text("We could move an image around the screen as well, for example when a button is selected or the user has completed an action")
                        .fontWeight(.light)
                        .font(.title2)
                    HStack {
                        Button(action: {
                            isActive4.toggle()
                        }, label: {
                            Image(systemName: "play.circle")
                                .resizable()
                                .frame(width: 44, height: 44)
                        })
                        Spacer()
                        Image(systemName: "bonjour")
                            .resizable()
                            .offset(x: isActive4 ? (geometry.size.width + 80) : 0)
                            .animation(.easeInOut(duration: 1).repeatForever(),
                                       value: isActive4)
                            .frame(width: 80, height: 80)
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 200)
        }
    }
}

#Preview {
    IconsAnimationsView()
}
