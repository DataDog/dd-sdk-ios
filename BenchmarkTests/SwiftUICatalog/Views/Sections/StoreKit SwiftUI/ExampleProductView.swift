//
//  ExampleProductView.swift
//  SwiftUICatalog
//
//  Created by Barbara Rodeker on 2023-10-19.
//

import SwiftUI
import StoreKit

/// Checkout this view in https://developer.apple.com/videos/play/wwdc2023/10013/
struct ExampleProductView: View {
    
    /// identifier of the product taken locally from the StoreKitConfiguration
    private var productId: String
    /// A custom image can be set for every product, in case that the image from App Store connect can no be accessed, this image can be used instead
    private var productImageName: String
    
    
    // MARK: - BODY
    
    var body: some View {
        PageContainer(content:
                        VStack(alignment: .leading) {
            DocumentationLinkView(link: "https://developer.apple.com/videos/play/wwdc2023/10013/", name: "PRODUCT VIEW")
            Text("You can preview the main blocks. For a real product overview insert your own in-app purchases identifiers in code.")
                .modifier(Divided())
            customizedLoadingView
                .modifier(Divided())
            customStyleViewReDrawing
                .modifier(Divided())
            customStyleView
                .modifier(Divided())
            compactProductView
                .modifier(Divided())
            largeProductView
                .modifier(Divided())
            regularProductView
                .modifier(Divided())
            ContributedByView(name: "Barbara Martina",
                              link: "https://github.com/barbaramartina")
            .padding(.top, 80)
            
        } // end of scroll view
        )
        // end of container
    }
    
    // MARK: - OTHER VIEWS
    
    private var productImage: some View {
        Image(systemName: productImageName)
            .resizable()
            .scaledToFit()
            .overlay(
                Color.gray
                    .opacity(0.5)
            )
            .clipShape(Circle())
            .frame(width: 120, height: 120)
    }
    
    /// a view with a custom ProductViewStyle showing a spinner while loading
    private var customStyleView: some View {
        VStack(alignment: .leading)  {
            HStack {
                Text("Compact Product Style with self configuration")
                    .fontWeight(.heavy)
                    .font(.title)
                Spacer()
            }
            ProductView(id: productId) {
                productImage
            }                
            .productViewStyle(SpinnerWhenLoadingStyle())
        }
    }
    
    /// A custom product style, where we also re-draw the view elements (not just style some of the loading phases)
    private var customStyleViewReDrawing: some View {
        VStack(alignment: .leading)  {
            HStack {
                Text("Compact Product Style re-drawing elements")
                    .fontWeight(.heavy)
                    .font(.title)
                Spacer()
            }
            ProductView(id: productId) {
                productImage
            }
            .productViewStyle(CustomProductViewStyle())
        }
    }
    
    /// A product view with a spinner for the "loading" phase
    private var customizedLoadingView: some View {
        VStack(alignment: .leading)  {
            HStack {
                Text("Compact Product Style with customized loading and background")
                    .fontWeight(.heavy)
                Spacer()
            }
            ProductView(id: productId) { phase in
                switch phase {
                case .loading:
                    ProgressView()
                case .failure(let error):
                    VStack {
                        Text("ERROR: \(error.localizedDescription)")
                    }
                case .unavailable:
                    productImage
                case .success(let promotedIcon): promotedIcon
                @unknown default:
                    productImage
                    
                }
            } placeholderIcon: {
                // When product is loading/unavailable
                ProgressView()
                    .frame(width: 120, height: 120)
            }
            .padding(.vertical, Style.VerticalPadding.large.rawValue)
            .padding(.horizontal, Style.HorizontalPadding.medium.rawValue)
            .background(.regularMaterial,
                        in: .rect(cornerRadius: 8))
        }
    }
    
    /// A regular layour for presenting a product
    private var regularProductView: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Regular Product Style")
                    .fontWeight(.heavy)
                    .font(.title)
                Spacer()
            }
            ProductView(id: productId) {
                productImage
            }
            .productViewStyle(.regular)
        }
    }
    
    /// A product view with a compact style
    private var compactProductView: some View {
        VStack(alignment: .leading)  {
            HStack {
                Text("Compact Product Style")
                    .fontWeight(.heavy)
                    .font(.title)
                Spacer()
            }
            ProductView(id: productId) {
                productImage
            }
            .productViewStyle(.compact)
        }
    }
    
    /// A product view with a large presentation style
    private var largeProductView: some View {
        VStack(alignment: .leading)  {
            HStack {
                Text("Large Product Style")
                    .fontWeight(.heavy)
                    .font(.title)
                Spacer()
            }
            ProductView(id: productId) {
                productImage
            }
            .productViewStyle(.large)
        }
    }
    
    // MARK: - INIT
    
    init(productId: String, productImageName: String) {
        self.productId = productId
        self.productImageName = productImageName
    }
    
}

#Preview {
    ExampleProductView(productId: "product.consumable.example.1", productImageName: "hands.and.sparkles.fill")
}

// MARK: - SpinnerWhenLoadingStyle

struct SpinnerWhenLoadingStyle: ProductViewStyle {
    public func makeBody(configuration: Configuration) -> some View {
        switch configuration.state {
        case .loading:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
            
        default:
            ProductView(configuration)
        }
    }
}

// MARK: - CustomProductViewStyle

struct CustomProductViewStyle: ProductViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        
        switch configuration.state {
        case .loading:
            ProgressView()
        case .unavailable:
            Text("product unavailable")
        case .failure(let error):
            Text("Error while loading the product: \(error.localizedDescription)")
        case .success(let product):
            VStack(alignment: .center) {
                Text(product.displayName)
                    .font(.title)
                    .foregroundColor(.white)
                Text(product.description)
                    .font(.subheadline)
                    .foregroundColor(.white)
                configuration.icon
                Button(product.displayPrice){}
                    .tint(.blue)
            }
            .padding()
            .background(content: {
                LinearGradient(colors: [.yellow, .blue, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
            })
        @unknown default:
            fatalError()
        }
    }
}
