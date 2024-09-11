/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that demonstrates how to use a default `UIToolbar`.
*/

import UIKit

class DefaultToolbarViewController: UIViewController {
    // MARK: - Properties

    @IBOutlet weak var toolbar: UIToolbar!

    // MARK: - View Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()

		let toolbarButtonItems = [
			trashBarButtonItem,
			flexibleSpaceBarButtonItem,
			customTitleBarButtonItem
		]
		toolbar.setItems(toolbarButtonItems, animated: true)
    }

    // MARK: - UIBarButtonItem Creation and Configuration

    var trashBarButtonItem: UIBarButtonItem {
        return UIBarButtonItem(barButtonSystemItem: .trash,
                               target: self,
                               action: #selector(DefaultToolbarViewController.barButtonItemClicked(_:)))
    }

    var flexibleSpaceBarButtonItem: UIBarButtonItem {
        return UIBarButtonItem(barButtonSystemItem: .flexibleSpace,
                               target: nil,
                               action: nil)
    }

    func menuHandler(action: UIAction) {
        Swift.debugPrint("Menu Action '\(action.title)'")
    }
    
    var customTitleBarButtonItem: UIBarButtonItem {
        let buttonMenu = UIMenu(title: "",
                                children: (1...5).map {
                                   UIAction(title: "Option \($0)", handler: menuHandler)
                                })
        return UIBarButtonItem(image: UIImage(systemName: "list.number"), menu: buttonMenu)
    }

    // MARK: - Actions

    @objc
    func barButtonItemClicked(_ barButtonItem: UIBarButtonItem) {
        Swift.debugPrint("A bar button item on the default toolbar was clicked: \(barButtonItem).")
    }
}
