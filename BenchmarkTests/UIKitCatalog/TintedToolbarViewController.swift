/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that demonstrates how to customize a `UIToolbar`.
*/

import UIKit

class TintedToolbarViewController: UIViewController {
    // MARK: - Properties
    
    @IBOutlet weak var toolbar: UIToolbar!

    // MARK: - View Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // See the `UIBarStyle` enum for more styles, including `.Default`.
        toolbar.barStyle = .black
        toolbar.isTranslucent = false
		
        toolbar.tintColor = UIColor.systemGreen
        toolbar.backgroundColor = UIColor.systemBlue
		
        let toolbarButtonItems = [
            refreshBarButtonItem,
            flexibleSpaceBarButtonItem,
            actionBarButtonItem
        ]
        toolbar.setItems(toolbarButtonItems, animated: true)
    }
    
    // MARK: - `UIBarButtonItem` Creation and Configuration

    var refreshBarButtonItem: UIBarButtonItem {
        return UIBarButtonItem(barButtonSystemItem: .refresh,
                               target: self,
                               action: #selector(TintedToolbarViewController.barButtonItemClicked(_:)))
    }

    var flexibleSpaceBarButtonItem: UIBarButtonItem {
        // Note that there's no target/action since this represents empty space.
        return UIBarButtonItem(barButtonSystemItem: .flexibleSpace,
                               target: nil,
                               action: nil)
    }

    var actionBarButtonItem: UIBarButtonItem {
        return UIBarButtonItem(barButtonSystemItem: .action,
                               target: self,
                               action: #selector(TintedToolbarViewController.actionBarButtonItemClicked(_:)))
    }

    // MARK: - Actions

    @objc
    func barButtonItemClicked(_ barButtonItem: UIBarButtonItem) {
        Swift.debugPrint("A bar button item on the tinted toolbar was clicked: \(barButtonItem).")
    }
    
    @objc
    func actionBarButtonItemClicked(_ barButtonItem: UIBarButtonItem) {
        if let image = UIImage(named: "Flowers_1", in: .module, compatibleWith: nil) {
            let activityItems = ["Shared piece of text", image] as [Any]
            
            let activityViewController =
                UIActivityViewController(activityItems: activityItems, applicationActivities: nil)

            activityViewController.popoverPresentationController?.barButtonItem = barButtonItem
            present(activityViewController, animated: true, completion: nil)
        }
    }
    
}
