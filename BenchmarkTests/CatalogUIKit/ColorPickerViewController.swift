/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that demonstrates how to use `UIColorPickerViewController`.
*/

import UIKit

class ColorPickerViewController: UIViewController, UIColorPickerViewControllerDelegate {

    // MARK: - Properties

    var colorWell: UIColorWell!
    var colorPicker: UIColorPickerViewController!
    
    @IBOutlet var pickerButton: UIButton! // UIButton to present the picker.
    @IBOutlet var pickerWellView: UIView! // UIView placeholder to hold the UIColorWell.
    
    @IBOutlet var colorView: UIView!
        
    // MARK: - View Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        configureColorPicker()
        configureColorWell()
        
        // For iOS, the picker button in the main view is not used, the color picker is presented from the navigation bar.
        if navigationController?.traitCollection.userInterfaceIdiom != .mac {
            pickerButton.isHidden = true
        }
    }
    
    // MARK: - UIColorWell
    
    // Update the color view from the color well chosen action.
    func colorWellHandler(action: UIAction) {
        if let colorWell = action.sender as? UIColorWell {
            colorView.backgroundColor = colorWell.selectedColor
        }
    }
    
    func configureColorWell() {
        
        /** Note: Both color well and picker buttons achieve the same thing, presenting the color picker.
            But one presents it with a color well control, the other by a bar button item.
         */
        let colorWellAction = UIAction(title: "", handler: colorWellHandler)
        colorWell =
            UIColorWell(frame: CGRect(x: 0, y: 0, width: 32, height: 32), primaryAction: colorWellAction)

        // For Mac Catalyst, the UIColorWell is placed in the main view.
        if navigationController?.traitCollection.userInterfaceIdiom == .mac {
            pickerWellView.addSubview(colorWell)
        } else {
            // For iOS, the UIColorWell is placed inside the navigation bar as a UIBarButtonItem.
            let colorWellBarItem = UIBarButtonItem(customView: colorWell)
            let fixedBarItem = UIBarButtonItem.fixedSpace(20.0)
            navigationItem.rightBarButtonItems!.append(fixedBarItem)
            navigationItem.rightBarButtonItems!.append(colorWellBarItem)
        }
    }

    // MARK: - UIColorPickerViewController

    func configureColorPicker() {
        colorPicker = UIColorPickerViewController()
        colorPicker.supportsAlpha = true
        colorPicker.selectedColor = UIColor.blue
        colorPicker.delegate = self
    }
    
    // Present the color picker from the UIBarButtonItem, iOS only.
    // This will present it as a popover (preferred), or for compact mode as a modal sheet.
    @IBAction func presentColorPickerByBarButton(_ sender: UIBarButtonItem) {
        colorPicker.modalPresentationStyle = UIModalPresentationStyle.popover // will display as popover for iPad or sheet for compact screens.
        let popover: UIPopoverPresentationController = colorPicker.popoverPresentationController!
        popover.barButtonItem = sender
        present(colorPicker, animated: true, completion: nil)
    }
    
    // Present the color picker from the UIButton, Mac Catalyst only.
    // This will present it as a popover (preferred), or for compact mode as a modal sheet.
    @IBAction func presentColorPickerByButton(_ sender: UIButton) {
        colorPicker.modalPresentationStyle = UIModalPresentationStyle.popover
        if let popover = colorPicker.popoverPresentationController {
            popover.sourceView = sender
            present(colorPicker, animated: true, completion: nil)
        }
    }
    
    // MARK: - UIColorPickerViewControllerDelegate
    
    // Color returned from the color picker via UIBarButtonItem - iOS 15.0
    @available(iOS 15.0, *)
    func colorPickerViewController(_ viewController: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
        // User has chosen a color.
        let chosenColor = viewController.selectedColor
        colorView.backgroundColor = chosenColor
        
        // Dismiss the color picker if the conditions are right:
        // 1) User is not doing a continuous pick (tap and drag across multiple colors).
        // 2) Picker is presented on a non-compact device.
        //
        // Use the following check to determine how the color picker was presented (modal or popover).
        // For popover, we want to dismiss it when a color is locked.
        // For modal, the picker has a close button.
        //
        if !continuously {
            if traitCollection.horizontalSizeClass != .compact {
                viewController.dismiss(animated: true, completion: {
                    Swift.debugPrint("\(chosenColor)")
                })
            }
        }
    }

    // Color returned from the color picker - iOS 14.x and earlier.
    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        // User has chosen a color.
        let chosenColor = viewController.selectedColor
        colorView.backgroundColor = chosenColor
        
        // Use the following check to determine how the color picker was presented (modal or popover).
        // For popover, we want to dismiss it when a color is locked.
        // For modal, the picker has a close button.
        //
        if traitCollection.horizontalSizeClass != .compact {
            viewController.dismiss(animated: true, completion: {
                Swift.debugPrint("\(chosenColor)")
            })
        }
    }
    
    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        /** In presentations (except popovers) the color picker shows a close button. If the close button is tapped,
            the view controller is dismissed and `colorPickerViewControllerDidFinish:` is called. Can be used to
            animate alongside the dismissal.
        */
    }

}
