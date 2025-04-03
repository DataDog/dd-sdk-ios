/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that demonstrates how to use `UIImageView`.
*/

import UIKit

class ImageViewController: UIViewController {
    // MARK: - View Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureImageView()
    }
    
    // MARK: - Configuration
    
    func configureImageView() {
        // The root view of the view controller is set in Interface Builder and is an UIImageView.
        if let imageView = view as? UIImageView {
            // Fetch the images (each image is of the format Flowers_number).
            imageView.animationImages = (1...2).map { UIImage(named: "Flowers_\($0)", in: .module, compatibleWith: nil)! }

            // We want the image to be scaled to the correct aspect ratio within imageView's bounds.
            imageView.contentMode = .scaleAspectFit
            
            imageView.animationDuration = 5
            imageView.startAnimating()
            
            imageView.isAccessibilityElement = true
            imageView.accessibilityLabel = NSLocalizedString("Animated", bundle: .module, comment: "")
            
            if #available(iOS 15, *) {
                // This case uses UIToolTipInteraction which is available on iOS 15 or later.
                let interaction =
                    UIToolTipInteraction(defaultToolTip: NSLocalizedString("ImageToolTipTitle", bundle: .module, comment: ""))
                imageView.addInteraction(interaction)
            }
        }
    }
}
