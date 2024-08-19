/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that demonstrates how to use `UITextView`.
*/

import UIKit

class TextViewController: UIViewController {
    // MARK: - Properties
    
    @IBOutlet weak var textView: UITextView!
    
    /// Used to adjust the text view's height when the keyboard hides and shows.
    @IBOutlet weak var textViewBottomLayoutGuideConstraint: NSLayoutConstraint!

    lazy var font = UIFont(
        descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: UIFont.TextStyle.body),
        size: 0)

    // MARK: - View Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        configureTextView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Listen for changes to keyboard visibility so that we can adjust the text view's height accordingly.
        let notificationCenter = NotificationCenter.default

        notificationCenter.addObserver(self,
                                       selector: #selector(TextViewController.handleKeyboardNotification(_:)),
                                       name: UIResponder.keyboardWillShowNotification,
                                       object: nil)
        
        notificationCenter.addObserver(self,
                                       selector: #selector(TextViewController.handleKeyboardNotification(_:)),
                                       name: UIResponder.keyboardWillHideNotification,
                                       object: nil)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        let notificationCenter = NotificationCenter.default
        notificationCenter.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        notificationCenter.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    // MARK: - Keyboard Event Notifications

    @objc
    func handleKeyboardNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }

        // Get the animation duration.
        var animationDuration: TimeInterval = 0
        if let value = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber {
           animationDuration = value.doubleValue
        }

        // Convert the keyboard frame from screen to view coordinates.
        var keyboardScreenBeginFrame = CGRect()
        if let value = (userInfo[UIResponder.keyboardFrameBeginUserInfoKey] as? NSValue) {
            keyboardScreenBeginFrame = value.cgRectValue
        }
        
        var keyboardScreenEndFrame = CGRect()
        if let value = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue) {
            keyboardScreenEndFrame = value.cgRectValue
        }
        
        let keyboardViewBeginFrame = view.convert(keyboardScreenBeginFrame, from: view.window)
        let keyboardViewEndFrame = view.convert(keyboardScreenEndFrame, from: view.window)
        
        let originDelta = keyboardViewEndFrame.origin.y - keyboardViewBeginFrame.origin.y
        
        // The text view should be adjusted, update the constant for this constraint.
        textViewBottomLayoutGuideConstraint.constant -= originDelta

        // Inform the view that its autolayout constraints have changed and the layout should be updated.
        view.setNeedsUpdateConstraints()

        // Animate updating the view's layout by calling layoutIfNeeded inside a `UIViewPropertyAnimator` animation block.
		let textViewAnimator = UIViewPropertyAnimator(duration: animationDuration, curve: .easeIn, animations: { [weak self] in
			self?.view.layoutIfNeeded()
		})
		textViewAnimator.startAnimation()
		
        // Scroll to the selected text once the keyboard frame changes.
        let selectedRange = textView.selectedRange
        textView.scrollRangeToVisible(selectedRange)
    }

    // MARK: - Configuration
    
    func reflowTextAttributes() {
        var entireTextColor = UIColor.black
        
        // The text should be white in dark mode.
        if self.view.traitCollection.userInterfaceStyle == .dark {
            entireTextColor = UIColor.white
        }
        let entireAttributedText = NSMutableAttributedString(attributedString: textView.attributedText!)
        let entireRange = NSRange(location: 0, length: entireAttributedText.length)
        entireAttributedText.addAttribute(NSAttributedString.Key.foregroundColor, value: entireTextColor, range: entireRange)
        textView.attributedText = entireAttributedText
        
        /** Modify some of the attributes of the attributed string.
            You can modify these attributes yourself to get a better feel for what they do.
            Note that the initial text is visible in the storyboard.
         */
        let attributedText = NSMutableAttributedString(attributedString: textView.attributedText!)
        
        /** Use NSString so the result of rangeOfString is an NSRange, not Range<String.Index>.
            This will then be the correct type to then pass to the addAttribute method of NSMutableAttributedString.
         */
        let text = textView.text! as NSString
        
        // Find the range of each element to modify.
        let boldRange = text.range(of: NSLocalizedString("bold", bundle: .module, comment: ""))
        let highlightedRange = text.range(of: NSLocalizedString("highlighted", bundle: .module, comment: ""))
        let underlinedRange = text.range(of: NSLocalizedString("underlined", bundle: .module, comment: ""))
        let tintedRange = text.range(of: NSLocalizedString("tinted", bundle: .module, comment: ""))
        
        // Add bold attribute. Take the current font descriptor and create a new font descriptor with an additional bold trait.
        let boldFontDescriptor = font.fontDescriptor.withSymbolicTraits(.traitBold)
        let boldFont = UIFont(descriptor: boldFontDescriptor!, size: 0)
        attributedText.addAttribute(NSAttributedString.Key.font, value: boldFont, range: boldRange)
        
        // Add highlight attribute.
        attributedText.addAttribute(NSAttributedString.Key.backgroundColor, value: UIColor.systemGreen, range: highlightedRange)
        
        // Add underline attribute.
        attributedText.addAttribute(NSAttributedString.Key.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: underlinedRange)
        
        // Add tint color.
        attributedText.addAttribute(NSAttributedString.Key.foregroundColor, value: UIColor.systemBlue, range: tintedRange)

        textView.attributedText = attributedText
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        // With the background change, we need to re-apply the text attributes.
        reflowTextAttributes()
    }
    
    func symbolAttributedString(name: String) -> NSAttributedString {
        let symbolAttachment = NSTextAttachment()
        if let symbolImage = UIImage(systemName: name)?.withRenderingMode(.alwaysTemplate) {
            symbolAttachment.image = symbolImage
        }
        return NSAttributedString(attachment: symbolAttachment)
    }
    
    @available(iOS 15.0, *)
    func multiColorSymbolAttributedString(name: String) -> NSAttributedString {
        let symbolAttachment = NSTextAttachment()
        let palleteSymbolConfig = UIImage.SymbolConfiguration(paletteColors: [UIColor.systemOrange, UIColor.systemRed])
        if let symbolImage = UIImage(systemName: name)?.withConfiguration(palleteSymbolConfig) {
            symbolAttachment.image = symbolImage
        }
        return NSAttributedString(attachment: symbolAttachment)
    }
    
    func configureTextView() {
        textView.font = font
        textView.backgroundColor = UIColor(named: "text_view_background")
        
        textView.isScrollEnabled = true

        // Apply different attributes to the text (bold, tinted, underline, etc.).
        reflowTextAttributes()
        
        // Insert symbols as image attachments.
        let text = textView.text! as NSString
        let attributedText = NSMutableAttributedString(attributedString: textView.attributedText!)
        let symbolsSearchRange = text.range(of: NSLocalizedString("symbols", bundle: .module, comment: ""))
        var insertPoint = symbolsSearchRange.location + symbolsSearchRange.length
        attributedText.insert(symbolAttributedString(name: "heart"), at: insertPoint)
        insertPoint += 1
        attributedText.insert(symbolAttributedString(name: "heart.fill"), at: insertPoint)
        insertPoint += 1
        attributedText.insert(symbolAttributedString(name: "heart.slash"), at: insertPoint)
        
        // Multi-color SF Symbols only in iOS 15 or later.
        if #available(iOS 15, *) {
            insertPoint += 1
            attributedText.insert(multiColorSymbolAttributedString(name: "arrow.up.heart.fill"), at: insertPoint)
        }
        
        // Add the image as an attachment.
        if let image = UIImage(named: "text_view_attachment", in: .module, compatibleWith: nil) {
            let textAttachment = NSTextAttachment()
            textAttachment.image = image
            textAttachment.bounds = CGRect(origin: CGPoint.zero, size: image.size)
            let textAttachmentString = NSAttributedString(attachment: textAttachment)
            attributedText.append(textAttachmentString)
            textView.attributedText = attributedText
        }
        
        /** When turned on, this changes the rendering scale of the text to match the standard text scaling
            and preserves the original font point sizes when the contents of the text view are copied to the pasteboard.
            Apps that show a lot of text content, such as a text viewer or editor, should turn this on and use the standard text scaling.
         */
        textView.usesStandardTextScaling = true
    }

    // MARK: - Actions

    @objc
    func doneBarButtonItemClicked() {
        // Dismiss the keyboard by removing it as the first responder.
        textView.resignFirstResponder()

        navigationItem.setRightBarButton(nil, animated: true)
    }
}

// MARK: - UITextViewDelegate

extension TextViewController: UITextViewDelegate {
	func textViewDidBeginEditing(_ textView: UITextView) {
		// Provide a "Done" button for the user to end text editing.
		let doneBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
		                                        target: self,
		                                        action: #selector(TextViewController.doneBarButtonItemClicked))
		
		navigationItem.setRightBarButton(doneBarButtonItem, animated: true)
	}
	
}
