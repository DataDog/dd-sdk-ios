/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that demonstrates how to use `UIVisualEffectView`.
*/

import UIKit

class VisualEffectViewController: UIViewController {
    // MARK: - Properties
    
    @IBOutlet var imageView: UIImageView!
    
    private var visualEffect: UIVisualEffectView = {
        let vev = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        vev.translatesAutoresizingMaskIntoConstraints = false
        return vev
    }()

    private var textView: UITextView = {
        let textView = UITextView(frame: CGRect())
        textView.font = UIFont.systemFont(ofSize: 14)
        textView.text = NSLocalizedString("VisualEffectTextContent", bundle: .module, comment: "")
        
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = UIColor.clear
        if let fontDescriptor = UIFontDescriptor
            .preferredFontDescriptor(withTextStyle: UIFont.TextStyle.body)
            .withSymbolicTraits(UIFontDescriptor.SymbolicTraits.traitLooseLeading) {
                   let looseLeadingFont = UIFont(descriptor: fontDescriptor, size: 0)
                   textView.font = looseLeadingFont
               }
        return textView
    }()
    
    // MARK: - View Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Add the visual effect view in the same area covering the image view.
        view.addSubview(visualEffect)
        NSLayoutConstraint.activate([
            visualEffect.topAnchor.constraint(equalTo: imageView.topAnchor),
            visualEffect.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: imageView.bottomAnchor)
        ])
        
        // Add a text view as a subview to the visual effect view.
        visualEffect.contentView.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: visualEffect.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: visualEffect.safeAreaLayoutGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: visualEffect.safeAreaLayoutGuide.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: visualEffect.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        if #available(iOS 15, *) {
            // Use UIToolTipInteraction which is available on iOS 15 or later, add it to the image view.
            let toolTipString = NSLocalizedString("VisualEffectToolTipTitle", bundle: .module, comment: "")
            let interaction = UIToolTipInteraction(defaultToolTip: toolTipString)
            imageView.addInteraction(interaction)
        }
    }

}
