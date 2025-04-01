/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that demonstrates how to use a customized `UIPageControl`.
*/

import UIKit

class CustomPageControlViewController: UIViewController {
    // MARK: - Properties

    @IBOutlet weak var pageControl: UIPageControl!

    @IBOutlet weak var colorView: UIView!

    // Colors that correspond to the selected page. Used as the background color for `colorView`.
    let colors = [
        UIColor.black,
        UIColor.systemGray,
        UIColor.systemRed,
        UIColor.systemGreen,
        UIColor.systemBlue,
        UIColor.systemPink,
        UIColor.systemYellow,
        UIColor.systemIndigo,
        UIColor.systemOrange,
        UIColor.systemPurple,
        UIColor.systemGray2,
        UIColor.systemGray3,
        UIColor.systemGray4,
        UIColor.systemGray5
    ]
    
    let images = [
        UIImage(systemName: "square.fill"),
        UIImage(systemName: "square"),
        UIImage(systemName: "triangle.fill"),
        UIImage(systemName: "triangle"),
        UIImage(systemName: "circle.fill"),
        UIImage(systemName: "circle"),
        UIImage(systemName: "star.fill"),
        UIImage(systemName: "star"),
        UIImage(systemName: "staroflife"),
        UIImage(systemName: "staroflife.fill"),
        UIImage(systemName: "heart.fill"),
        UIImage(systemName: "heart"),
        UIImage(systemName: "moon"),
        UIImage(systemName: "moon.fill")
    ]

    // MARK: - View Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        configurePageControl()
        pageControlValueDidChange()
    }

    // MARK: - Configuration

    func configurePageControl() {
        // The total number of available pages is based on the number of available colors.
        pageControl.numberOfPages = colors.count
        pageControl.currentPage = 2
        
        pageControl.currentPageIndicatorTintColor = UIColor.systemPurple

        // Prominent background style.
        pageControl.backgroundStyle = .prominent
        
        // Set custom indicator images.
        for (index, image) in images.enumerated() {
            pageControl.setIndicatorImage(image, forPage: index)
        }

        pageControl.addTarget(self,
                              action: #selector(PageControlViewController.pageControlValueDidChange),
                              for: .valueChanged)
    }
    
    // MARK: - Actions

    @objc
    func pageControlValueDidChange() {
        // Note: gesture swiping between pages is provided by `UIPageViewController` and not `UIPageControl`.
        Swift.debugPrint("The page control changed its current page to \(pageControl.currentPage).")

        colorView.backgroundColor = colors[pageControl.currentPage]
    }
}
