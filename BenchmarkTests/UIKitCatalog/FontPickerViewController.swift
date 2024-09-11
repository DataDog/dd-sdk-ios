/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that demonstrates how to use `UIFontPickerViewController`.
*/

import UIKit

class FontPickerViewController: UIViewController {

    // MARK: - Properties

    var fontPicker: UIFontPickerViewController!
    var textFormatter: UITextFormattingCoordinator!
    
    @IBOutlet var fontLabel: UILabel!
    @IBOutlet var textFormatterButton: UIButton!
    
    // MARK: - View Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        fontLabel.text = NSLocalizedString("SampleFontTitle", bundle: .module, comment: "")
        
        configureFontPicker()
        
        if traitCollection.userInterfaceIdiom != .mac {
            // UITextFormattingCoordinator's toggleFontPanel is available only for macOS.
            textFormatterButton.isHidden = true
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        configureTextFormatter()
    }

    func configureFontPicker() {
        let configuration = UIFontPickerViewController.Configuration()
        configuration.includeFaces = true
        configuration.displayUsingSystemFont = false
        configuration.filteredTraits = [.classModernSerifs]

        fontPicker = UIFontPickerViewController(configuration: configuration)
        fontPicker.delegate = self
        fontPicker.modalPresentationStyle = UIModalPresentationStyle.popover
    }
    
    func configureTextFormatter() {
        if textFormatter == nil {
            guard let scene = self.view.window?.windowScene else { return }
            let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key.font: fontLabel.font as Any]
            textFormatter = UITextFormattingCoordinator(for: scene)
            textFormatter.delegate = self
            textFormatter.setSelectedAttributes(attributes, isMultiple: true)
        }
    }

    @IBAction func presentFontPicker(_ sender: Any) {
        if let button = sender as? UIButton {
            let popover: UIPopoverPresentationController = fontPicker.popoverPresentationController!
            popover.sourceView = button
            present(fontPicker, animated: true, completion: nil)
        }
    }
    
    @IBAction func presentTextFormattingCoordinator(_ sender: Any) {
        if !UITextFormattingCoordinator.isFontPanelVisible {
            UITextFormattingCoordinator.toggleFontPanel(sender)
        }
    }
    
}

// MARK: - UIFontPickerViewControllerDelegate

extension FontPickerViewController: UIFontPickerViewControllerDelegate {
    
    func fontPickerViewControllerDidCancel(_ viewController: UIFontPickerViewController) {
        //..
    }

    func fontPickerViewControllerDidPickFont(_ viewController: UIFontPickerViewController) {
        guard let fontDescriptor = viewController.selectedFontDescriptor else { return }
        let font = UIFont(descriptor: fontDescriptor, size: 28.0)
        fontLabel.font = font
    }
    
}

// MARK: - UITextFormattingCoordinatorDelegate

extension FontPickerViewController: UITextFormattingCoordinatorDelegate {
    
    override func updateTextAttributes(conversionHandler: ([NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any]) {
        guard let oldLabelText = fontLabel.attributedText else { return }
        let newString = NSMutableAttributedString(string: oldLabelText.string)
        oldLabelText.enumerateAttributes(in: NSRange(location: 0, length: oldLabelText.length),
                                         options: []) { (attributeDictionary, range, stop) in
            newString.setAttributes(conversionHandler(attributeDictionary), range: range)
        }
        fontLabel.attributedText = newString
    }
    
}
