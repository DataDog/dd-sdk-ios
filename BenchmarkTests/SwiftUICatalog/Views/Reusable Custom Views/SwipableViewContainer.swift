//
//  SwipableView.swift
//  SwiftUICatalog
//
//  Created by Barbara Rodeker on 2022-06-27.
//

import SwiftUI

struct SwipableViewContainer: View {
    
    @State var subviews: [TitleSubtitleIconView]
    
    /// a gesture to move the sub views around
    @GestureState private var dragState = DragState.inactive
    /// executed when the view is swipped left or right
    @State private var viewRemovalTransition = AnyTransition.trailingBottom
    /// the space to consider either from left or right, to determine when the view has to be removed from the stack
    private let dragAreaThreshold: CGFloat = 65.0
    
    
    // MARK: TOP VIEW
    
    private func isTopView(_ view: TitleSubtitleIconView) -> Bool {
        guard let index = subviews.firstIndex(where: { $0.id == view.id }) else {
            return false
        }
        return index == 0
    }
    
    // MARK: - DRAG STATES
    
    enum DragState {
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
        
        var isDragging: Bool {
            switch self {
            case .dragging:
                return true
            case .pressing, .inactive:
                return false
            }
        }
        
        var isPressing: Bool {
            switch self {
            case .pressing, .dragging:
                return true
            case .inactive:
                return false
            }
        }
    }
    
    var body: some View {
        
        ZStack {
            ForEach(subviews) { subview in
                
                subview
                    .zIndex(self.isTopView(subview) ? 1 : 0)
                    .offset(x: self.isTopView(subview) ?  self.dragState.translation.width : 0,
                            y: self.isTopView(subview) ?  self.dragState.translation.height : 0)
                    .scaleEffect(self.dragState.isDragging && self.isTopView(subview) ? 0.8 : 1.0)
                    .rotationEffect(Angle(degrees: self.isTopView(subview) ? Double(self.dragState.translation.width / 12) : 0))
                    .gesture(LongPressGesture(minimumDuration: 0.01)
                        .sequenced(before: DragGesture())
                        .updating(self.$dragState, body: { (value, state, transaction) in
                            switch value {
                            case .first(true):
                                state = .pressing
                            case .second(true, let drag):
                                state = .dragging(translation: drag?.translation ?? .zero)
                            default:
                                break
                            }
                        })
                             
                            .onChanged({ (value) in
                                guard case .second(true, let drag?) = value else {
                                    return
                                }
                                
                                if drag.translation.width < -self.dragAreaThreshold {
                                    self.viewRemovalTransition = .leadingBottom
                                }
                                
                                if drag.translation.width > self.dragAreaThreshold {
                                    self.viewRemovalTransition = .trailingBottom
                                }
                            })
                                .onEnded({ (value) in
                                    guard case .second(true, let drag?) = value else {
                                        return
                                    }
                                    
                                    if drag.translation.width < -self.dragAreaThreshold || drag.translation.width > self.dragAreaThreshold {
                                        self.subviews.removeFirst()
                                    }
                                })
                    ).transition(self.viewRemovalTransition)
            }
        }
        .padding(.horizontal, Style.HorizontalPadding.medium.rawValue)
    }
}

#Preview {
    SwipableViewContainer(subviews: [
        TitleSubtitleIconView(
            configuration: TitleSubtitleIconView.Configuration(
                backgroundColor: Color.brown,
                title: "Sun",
                titleFont: .title,
                titleWeight: .bold,
                subtitle: "The Sun is the star at the heart of our solar system. Its gravity holds the solar system together, keeping everything – from the biggest planets to the smallest",
                subtitleFont: .body,
                subtitleWeight: .regular,
                icon: "sun.max",
                iconSize: CGSize(width: 60, height: 60),
                iconVerticalAlignment: .top,
                iconHorizontalAlignment: .leading,
                paddingTop: 16,
                paddingLeading: 16,
                paddingTrailing: 16,
                paddingBottom: 16
            )
        ),
        TitleSubtitleIconView(
            configuration: TitleSubtitleIconView.Configuration(
                backgroundColor: Color.cyan, title: "snowflake",
                titleFont: .title,
                titleWeight: .bold,
                subtitle: "Snow comprises individual ice crystals that grow while suspended in the atmosphere—usually within clouds—and then fall",
                subtitleFont: .body,
                subtitleWeight: .regular,
                icon: "snowflake",
                iconSize: CGSize(width: 60, height: 60),
                iconVerticalAlignment: .top, 
                iconHorizontalAlignment: .trailing,
                paddingTop: 16,
                paddingLeading: 16,
                paddingTrailing: 16,
                paddingBottom: 16
            )
        ),

        TitleSubtitleIconView(
            configuration: TitleSubtitleIconView.Configuration(
                backgroundColor: Color.accentColor, 
                title: "Rain",
                titleFont: .title,
                titleWeight: .bold,
                subtitle: "Rain is water droplets that have condensed from atmospheric water vapor and then fall under gravity.",
                subtitleFont: .body,
                subtitleWeight: .regular,
                icon: "cloud.rain.circle",
                iconSize: CGSize(width: 60, height: 60),
                iconVerticalAlignment: .top,
                iconHorizontalAlignment: .center,
                paddingTop: 16,
                paddingLeading: 16,
                paddingTrailing: 16,
                paddingBottom: 16
            )
        )
    ])
}

// MARK: - AnyTransition

extension AnyTransition {
    static var trailingBottom: AnyTransition {
        AnyTransition.asymmetric(
            insertion: .identity,
            removal: AnyTransition.move(edge: .trailing).combined(with: .move(edge: .bottom)))
    }
    
    static var leadingBottom: AnyTransition {
        AnyTransition.asymmetric(
            insertion: .identity,
            removal: AnyTransition.move(edge: .leading).combined(with: .move(edge: .bottom)))
    }
    
}

// MARK: - SwipableView Example


struct SwipableViewExample: View, Identifiable {
    
    let id = UUID()
    let textContent: String
    
    var body: some View {
        
        VStack {
            Text(textContent)
            Image(systemName: "person")
                .frame(width: 200, height: 200, alignment: .center)
            Text(textContent)
            
        }
    }
    
}


