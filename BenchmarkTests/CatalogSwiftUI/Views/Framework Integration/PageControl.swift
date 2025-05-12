//
//  PageControl.swift
//  SwiftUICatalog
//
//  Created by Ali Ghayeni on 20.04.23.
//

import SwiftUI
import UIKit

/**
 https://developer.apple.com/documentation/swiftui/uiviewcontrollerrepresentable
 UIViewControllerRepresentable
 Create a structure that conforms to UIViewControllerRepresentable and implement the protocol requirements to include a UIViewController in your SwiftUI view hierarchy.
 */
struct PageControl: UIViewRepresentable {
    var numberOfPages: Int
    @Binding var currentPage: Int
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UIPageControl {
        let control = UIPageControl()
        control.numberOfPages = numberOfPages
        control.addTarget(
            context.coordinator,
            action: #selector(Coordinator.updateCurrentPage(sender:)),
            for: .valueChanged)
        
        return control
    }
    
    func updateUIView(_ uiView: UIPageControl, context: Context) {
        uiView.currentPage = currentPage
    }
    
    class Coordinator: NSObject {
        var control: PageControl
        
        init(_ control: PageControl) {
            self.control = control
        }
        
        @objc
        func updateCurrentPage(sender: UIPageControl) {
            control.currentPage = sender.currentPage
        }
    }
}
