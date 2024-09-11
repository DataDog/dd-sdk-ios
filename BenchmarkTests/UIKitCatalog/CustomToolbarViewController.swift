/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that demonstrates how to customize a `UIToolbar`.
*/

import UIKit

class CustomToolbarViewController: UIViewController {
    // MARK: - Properties

    @IBOutlet weak var toolbar: UIToolbar!

    // MARK: - View Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()

        let toolbarBackgroundImage = UIImage(named: "toolbar_background", in: .module, compatibleWith: nil)
        toolbar.setBackgroundImage(toolbarBackgroundImage, forToolbarPosition: .bottom, barMetrics: .default)
		
        let toolbarButtonItems = [
            customImageBarButtonItem,
            flexibleSpaceBarButtonItem,
            customBarButtonItem
        ]
        toolbar.setItems(toolbarButtonItems, animated: true)
    }
    
    // MARK: - UIBarButtonItem Creation and Configuration

    var customImageBarButtonItem: UIBarButtonItem {
        let customBarButtonItemImage = UIImage(systemName: "exclamationmark.triangle")

        let customImageBarButtonItem = UIBarButtonItem(image: customBarButtonItemImage,
                                                       style: .plain,
                                                       target: self,
                                                       action: #selector(CustomToolbarViewController.barButtonItemClicked(_:)))

        customImageBarButtonItem.tintColor = UIColor.systemPurple

        return customImageBarButtonItem
    }

    var flexibleSpaceBarButtonItem: UIBarButtonItem {
        // Note that there's no target/action since this represents empty space.
        return UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
    }

    var customBarButtonItem: UIBarButtonItem {
        let barButtonItem = UIBarButtonItem(title: NSLocalizedString("Button", bundle: .module, comment: ""),
                                            style: .plain,
                                            target: self,
                                            action: #selector(CustomToolbarViewController.barButtonItemClicked))

        let attributes = [
            NSAttributedString.Key.foregroundColor: UIColor.systemPurple
        ]
        barButtonItem.setTitleTextAttributes(attributes, for: [])

        return barButtonItem
    }

    // MARK: - Actions
    
    @objc
    func barButtonItemClicked(_ barButtonItem: UIBarButtonItem) {
        Swift.debugPrint("A bar button item on the custom toolbar was clicked: \(barButtonItem).")
    }

}
