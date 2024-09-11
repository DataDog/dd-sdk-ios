/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The view controller that demonstrates how to use `UIAlertController`.
*/

import UIKit

class AlertControllerViewController: UITableViewController {
    // MARK: - Properties

    weak var secureTextAlertAction: UIAlertAction?
    
	private enum StyleSections: Int {
		case alertStyleSection = 0
		case actionStyleSection
	}
	
	private enum AlertStyleTest: Int {
		// Alert style alerts.
		case showSimpleAlert = 0
		case showOkayCancelAlert
		case showOtherAlert
		case showTextEntryAlert
		case showSecureTextEntryAlert
	}
	
	private enum ActionSheetStyleTest: Int {
		// Action sheet style alerts.
		case showOkayCancelActionSheet = 0
		case howOtherActionSheet
	}
	
    private var textDidChangeObserver: Any? = nil
    
    // MARK: - UIAlertControllerStyleAlert Style Alerts

    /// Show an alert with an "OK" button.
    func showSimpleAlert() {
        let title = NSLocalizedString("A Short Title is Best", bundle: .module, comment: "")
        let message = NSLocalizedString("A message needs to be a short, complete sentence.", bundle: .module, comment: "")
        let cancelButtonTitle = NSLocalizedString("OK", bundle: .module, comment: "")

        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)

        // Create the action.
        let cancelAction = UIAlertAction(title: cancelButtonTitle, style: .cancel) { _ in
            Swift.debugPrint("The simple alert's cancel action occurred.")
        }

        // Add the action.
        alertController.addAction(cancelAction)

        present(alertController, animated: true, completion: nil)
    }
    
    /// Show an alert with an "OK" and "Cancel" button.
    func showOkayCancelAlert() {
        let title = NSLocalizedString("A Short Title is Best", bundle: .module, comment: "")
        let message = NSLocalizedString("A message needs to be a short, complete sentence.", bundle: .module, comment: "")
        let cancelButtonTitle = NSLocalizedString("Cancel", bundle: .module, comment: "")
        let otherButtonTitle = NSLocalizedString("OK", bundle: .module, comment: "")
        
        let alertCotroller = UIAlertController(title: title, message: message, preferredStyle: .alert)

        // Create the actions.
        let cancelAction = UIAlertAction(title: cancelButtonTitle, style: .cancel) { _ in
            Swift.debugPrint("The \"OK/Cancel\" alert's cancel action occurred.")
        }
        
        let otherAction = UIAlertAction(title: otherButtonTitle, style: .default) { _ in
            Swift.debugPrint("The \"OK/Cancel\" alert's other action occurred.")
        }
        
        // Add the actions.
        alertCotroller.addAction(cancelAction)
        alertCotroller.addAction(otherAction)

        present(alertCotroller, animated: true, completion: nil)
    }

    /// Show an alert with two custom buttons.
    func showOtherAlert() {
        let title = NSLocalizedString("A Short Title is Best", bundle: .module, comment: "")
        let message = NSLocalizedString("A message needs to be a short, complete sentence.", bundle: .module, comment: "")
        let cancelButtonTitle = NSLocalizedString("Cancel", bundle: .module, comment: "")
        let otherButtonTitleOne = NSLocalizedString("Choice One", bundle: .module, comment: "")
        let otherButtonTitleTwo = NSLocalizedString("Choice Two", bundle: .module, comment: "")
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        // Create the actions.
        let cancelAction = UIAlertAction(title: cancelButtonTitle, style: .cancel) { _ in
            Swift.debugPrint("The \"Other\" alert's cancel action occurred.")
        }
        
        let otherButtonOneAction = UIAlertAction(title: otherButtonTitleOne, style: .default) { _ in
            Swift.debugPrint("The \"Other\" alert's other button one action occurred.")
        }
        
        let otherButtonTwoAction = UIAlertAction(title: otherButtonTitleTwo, style: .default) { _ in
            Swift.debugPrint("The \"Other\" alert's other button two action occurred.")
        }
        
        // Add the actions.
        alertController.addAction(cancelAction)
        alertController.addAction(otherButtonOneAction)
        alertController.addAction(otherButtonTwoAction)
        
        present(alertController, animated: true, completion: nil)
    }

    /// Show a text entry alert with two custom buttons.
    func showTextEntryAlert() {
        let title = NSLocalizedString("A Short Title is Best", bundle: .module, comment: "")
        let message = NSLocalizedString("A message needs to be a short, complete sentence.", bundle: .module, comment: "")
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        // Add the text field for text entry.
        alertController.addTextField { _ in
            // If you need to customize the text field, you can do so here.
        }

        // Create the actions.
        let cancelButtonTitle = NSLocalizedString("Cancel", bundle: .module, comment: "")
        let cancelAction = UIAlertAction(title: cancelButtonTitle, style: .cancel) { _ in
            Swift.debugPrint("The \"Text Entry\" alert's cancel action occurred.")
        }
        
        let otherButtonTitle = NSLocalizedString("OK", bundle: .module, comment: "")
        let otherAction = UIAlertAction(title: otherButtonTitle, style: .default) { _ in
            Swift.debugPrint("The \"Text Entry\" alert's other action occurred.")
        }
        
        // Add the actions.
        alertController.addAction(cancelAction)
        alertController.addAction(otherAction)
        
        present(alertController, animated: true, completion: nil)
    }
    
    /// Show a secure text entry alert with two custom buttons.
    func showSecureTextEntryAlert() {
        let title = NSLocalizedString("A Short Title is Best", bundle: .module, comment: "")
        let message = NSLocalizedString("A message needs to be a short, complete sentence.", bundle: .module, comment: "")
        let cancelButtonTitle = NSLocalizedString("Cancel", bundle: .module, comment: "")
        let otherButtonTitle = NSLocalizedString("OK", bundle: .module, comment: "")
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        // Add the text field for the secure text entry.
        alertController.addTextField { textField in
            if let observer = self.textDidChangeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            /** Listen for changes to the text field's text so that we can toggle the current
                action's enabled property based on whether the user has entered a sufficiently
                secure entry.
            */
            self.textDidChangeObserver =
                NotificationCenter.default.addObserver(forName: UITextField.textDidChangeNotification,
                                                       object: textField,
                                                       queue: OperationQueue.main,
                                                       using: { (notification) in
                    if let textField = notification.object as? UITextField {
                        // Enforce a minimum length of >= 5 characters for secure text alerts.
                        if let alertAction = self.secureTextAlertAction {
                            if let text = textField.text {
                                alertAction.isEnabled = text.count >= 5
                            } else {
                                alertAction.isEnabled = false
                            }
                        }
                    }
            })

            textField.isSecureTextEntry = true
        }
		
        // Create the actions.
        let cancelAction = UIAlertAction(title: cancelButtonTitle, style: .cancel) { _ in
            Swift.debugPrint("The \"Secure Text Entry\" alert's cancel action occurred.")
        }
        
        let otherAction = UIAlertAction(title: otherButtonTitle, style: .default) { _ in
            Swift.debugPrint("The \"Secure Text Entry\" alert's other action occurred.")
        }
        
        /** The text field initially has no text in the text field, so we'll disable it for now.
            It will be re-enabled when the first character is typed.
        */
        otherAction.isEnabled = false
        
        /** Hold onto the secure text alert action to toggle the enabled / disabled
            state when the text changed.
        */
        secureTextAlertAction = otherAction
        
        // Add the actions.
        alertController.addAction(cancelAction)
        alertController.addAction(otherAction)
        
        present(alertController, animated: true, completion: nil)
    }
    
    // MARK: - UIAlertControllerStyleActionSheet Style Alerts
    
    // Show a dialog with an "OK" and "Cancel" button.
    func showOkayCancelActionSheet(_ selectedIndexPath: IndexPath) {
        let message = NSLocalizedString("A message needs to be a short, complete sentence.", bundle: .module, comment: "")
		let cancelButtonTitle = NSLocalizedString("Cancel", bundle: .module, comment: "")
        let destructiveButtonTitle = NSLocalizedString("Confirm", bundle: .module, comment: "")
        
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .actionSheet)
        
        // Create the actions.
        let cancelAction = UIAlertAction(title: cancelButtonTitle, style: .cancel) { _ in
            Swift.debugPrint("The \"OK/Cancel\" alert action sheet's cancel action occurred.")
        }
        
        let destructiveAction = UIAlertAction(title: destructiveButtonTitle, style: .default) { _ in
            Swift.debugPrint("The \"Confirm\" alert action sheet's destructive action occurred.")
        }
        
        // Add the actions.
        alertController.addAction(cancelAction)
        alertController.addAction(destructiveAction)
        
        // Configure the alert controller's popover presentation controller if it has one.
        if let popoverPresentationController = alertController.popoverPresentationController {
          	// Note for popovers the Cancel button is hidden automatically.
			
			// This method expects a valid cell to display from.
            let selectedCell = tableView.cellForRow(at: selectedIndexPath)!
            popoverPresentationController.sourceRect = selectedCell.frame
            popoverPresentationController.sourceView = view
            popoverPresentationController.permittedArrowDirections = .up
        }
        
        present(alertController, animated: true, completion: nil)
    }

    // Show a dialog with two custom buttons.
    func showOtherActionSheet(_ selectedIndexPath: IndexPath) {
        let message = NSLocalizedString("A message needs to be a short, complete sentence.", bundle: .module, comment: "")
		let destructiveButtonTitle = NSLocalizedString("Destructive Choice", bundle: .module, comment: "")
        let otherButtonTitle = NSLocalizedString("Safe Choice", bundle: .module, comment: "")
        
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .actionSheet)
        
        // Create the actions.
        let destructiveAction = UIAlertAction(title: destructiveButtonTitle, style: .destructive) { _ in
            Swift.debugPrint("The \"Other\" alert action sheet's destructive action occurred.")
        }
        let otherAction = UIAlertAction(title: otherButtonTitle, style: .default) { _ in
            Swift.debugPrint("The \"Other\" alert action sheet's other action occurred.")
        }
        
        // Add the actions.
        alertController.addAction(destructiveAction)
        alertController.addAction(otherAction)
        
        // Configure the alert controller's popover presentation controller if it has one.
        if let popoverPresentationController = alertController.popoverPresentationController {
            // Note for popovers the Cancel button is hidden automatically.
			
			// This method expects a valid cell to display from.
            let selectedCell = tableView.cellForRow(at: selectedIndexPath)!
            popoverPresentationController.sourceRect = selectedCell.frame
            popoverPresentationController.sourceView = view
            popoverPresentationController.permittedArrowDirections = .up
        }
        
        present(alertController, animated: true, completion: nil)
    }

}

// MARK: - UITableViewDelegate

extension AlertControllerViewController {
    
	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		switch indexPath.section {
		case StyleSections.alertStyleSection.rawValue:
			// Alert style.
			switch indexPath.row {
			case AlertStyleTest.showSimpleAlert.rawValue:
				showSimpleAlert()
			case AlertStyleTest.showOkayCancelAlert.rawValue:
				showOkayCancelAlert()
			case AlertStyleTest.showOtherAlert.rawValue:
				showOtherAlert()
			case AlertStyleTest.showTextEntryAlert.rawValue:
				showTextEntryAlert()
			case AlertStyleTest.showSecureTextEntryAlert.rawValue:
				showSecureTextEntryAlert()
			default: break
			}
		case StyleSections.actionStyleSection.rawValue:
			switch indexPath.row {
			// Action sheet style.
			case ActionSheetStyleTest.showOkayCancelActionSheet.rawValue:
				showOkayCancelActionSheet(indexPath)
			case ActionSheetStyleTest.howOtherActionSheet.rawValue:
				showOtherActionSheet(indexPath)
			default: break
			}
		default: break
		}

		tableView.deselectRow(at: indexPath, animated: true)
	}

}
