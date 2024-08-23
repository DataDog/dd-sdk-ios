/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Configuration functions for all the UIButtons found in ButtonViewController.
*/

import UIKit

extension ButtonViewController: UIToolTipInteractionDelegate {
    
    func configureSystemTextButton(_ button: UIButton) {
        button.setTitle(NSLocalizedString("Button", bundle: .module, comment: ""), for: [])
        button.addTarget(self, action: #selector(ButtonViewController.buttonClicked(_:)), for: .touchUpInside)
    }
    func configureSystemDetailDisclosureButton(_ button: UIButton) {
        // Nothing particular to set here, it's all been done in the storyboard.
        button.addTarget(self, action: #selector(ButtonViewController.buttonClicked(_:)), for: .touchUpInside)
    }
    func configureSystemContactAddButton(_ button: UIButton) {
        // Nothing particular to set here, it's all been done in the storyboard.
        button.addTarget(self, action: #selector(ButtonViewController.buttonClicked(_:)), for: .touchUpInside)
    }
    
    func configureCloseButton(_ button: UIButton) {
        // Nothing particular to set here, it's all been done in the storyboard.
        button.addTarget(self, action: #selector(ButtonViewController.buttonClicked(_:)), for: .touchUpInside)
    }
    
    @available(iOS 15.0, *)
    func configureStyleGrayButton(_ button: UIButton) {
        // Note this can be also be done in the storyboard for this button.
        let config = UIButton.Configuration.gray()
        button.configuration = config

        button.setTitle(NSLocalizedString("Button", bundle: .module, comment: ""), for: .normal)
        button.toolTip = NSLocalizedString("GrayStyleButtonToolTipTitle", bundle: .module, comment: "")
        
        button.addTarget(self, action: #selector(ButtonViewController.buttonClicked(_:)), for: .touchUpInside)
    }

    @available(iOS 15.0, *)
    func configureStyleTintedButton(_ button: UIButton) {
        // Note this can be also be done in the storyboard for this button.
        
        var config = UIButton.Configuration.tinted()
 
        /** To keep the look the same betwen iOS and macOS:
            For tinted color to work in Mac Catalyst, use UIBehavioralStyle as ".pad",
            Available in macOS 12 or later (Mac Catalyst 15.0 or later).
            Use this for controls that need to look the same between iOS and macOS.
        */
        if traitCollection.userInterfaceIdiom == .mac {
            button.preferredBehavioralStyle = .pad
        }
        
        // The following will make the button title red and background a lighter red.
        config.baseBackgroundColor = .systemRed
        config.baseForegroundColor = .systemRed
        
        button.setTitle(NSLocalizedString("Button", bundle: .module, comment: ""), for: .normal)
        button.toolTip = NSLocalizedString("TintedStyleButtonToolTipTitle", bundle: .module, comment: "")
        
        button.configuration = config
        
        button.addTarget(self, action: #selector(ButtonViewController.buttonClicked(_:)), for: .touchUpInside)
    }

    @available(iOS 15.0, *)
    func configureStyleFilledButton(_ button: UIButton) {
        // Note this can be also be done in the storyboard for this button.
        var config = UIButton.Configuration.filled()
        config.background.backgroundColor = .systemRed
        button.configuration = config
        
        button.setTitle(NSLocalizedString("Button", bundle: .module, comment: ""), for: .normal)
        button.toolTip = NSLocalizedString("FilledStyleButtonToolTipTitle", bundle: .module, comment: "")
        
        button.addTarget(self, action: #selector(ButtonViewController.buttonClicked(_:)), for: .touchUpInside)
    }
    
    @available(iOS 15.0, *)
    func configureCornerStyleButton(_ button: UIButton) {
        /** To keep the look the same betwen iOS and macOS:
            For cornerStyle to work in Mac Catalyst, use UIBehavioralStyle as ".pad",
            Available in macOS 12 or later (Mac Catalyst 15.0 or later).
            Use this for controls that need to look the same between iOS and macOS.
        */
        if traitCollection.userInterfaceIdiom == .mac {
            button.preferredBehavioralStyle = .pad
        }
        
        var config = UIButton.Configuration.gray()
        config.cornerStyle = .capsule
        button.configuration = config
        
        button.setTitle(NSLocalizedString("Button", bundle: .module, comment: ""), for: .normal)
        button.toolTip = NSLocalizedString("CapsuleStyleButtonToolTipTitle", bundle: .module, comment: "")
        
        button.addTarget(self, action: #selector(ButtonViewController.buttonClicked(_:)), for: .touchUpInside)
    }

    func configureImageButton(_ button: UIButton) {
        // To create this button in code you can use `UIButton.init(type: .system)`.

        // Set the tint color to the button's image.
        if let image = UIImage(systemName: "xmark") {
            let imageButtonNormalImage = image.withTintColor(.systemPurple)
            button.setImage(imageButtonNormalImage, for: .normal)
        }
                
        // Since this button title is just an image, add an accessibility label.
        button.accessibilityLabel = NSLocalizedString("X", bundle: .module, comment: "")
        
        if #available(iOS 15, *) {
            button.toolTip = NSLocalizedString("XButtonToolTipTitle", bundle: .module, comment: "")
        }
        
        button.addTarget(self, action: #selector(ButtonViewController.buttonClicked(_:)), for: .touchUpInside)
    }

    func configureAttributedTextSystemButton(_ button: UIButton) {
        let buttonTitle = NSLocalizedString("Button", bundle: .module, comment: "")
        
        // Set the button's title for normal state.
        let normalTitleAttributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key.strikethroughStyle: NSUnderlineStyle.single.rawValue
        ]
        
        let normalAttributedTitle = NSAttributedString(string: buttonTitle, attributes: normalTitleAttributes)
        button.setAttributedTitle(normalAttributedTitle, for: .normal)
        
        // Set the button's title for highlighted state (note this is not supported in Mac Catalyst).
        let highlightedTitleAttributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key.foregroundColor: UIColor.systemGreen,
            NSAttributedString.Key.strikethroughStyle: NSUnderlineStyle.thick.rawValue
        ]
        let highlightedAttributedTitle = NSAttributedString(string: buttonTitle, attributes: highlightedTitleAttributes)
        button.setAttributedTitle(highlightedAttributedTitle, for: .highlighted)

        button.addTarget(self, action: #selector(ButtonViewController.buttonClicked(_:)), for: .touchUpInside)
    }
    
    func configureSymbolButton(_ button: UIButton) {
        let buttonImage = UIImage(systemName: "person")
        
        if #available(iOS 15, *) {
            // For iOS 15 use the UIButtonConfiguration to set the image.
            var buttonConfig = UIButton.Configuration.plain()
            buttonConfig.image = buttonImage
            button.configuration = buttonConfig
            
            button.toolTip = NSLocalizedString("PersonButtonToolTipTitle", bundle: .module, comment: "")
        } else {
            button.setImage(buttonImage, for: .normal)
        }
        
        let config = UIImage.SymbolConfiguration(textStyle: .body, scale: .large)
        button.setPreferredSymbolConfiguration(config, forImageIn: .normal)
        
        // Since this button title is just an image, add an accessibility label.
        button.accessibilityLabel = NSLocalizedString("Person", bundle: .module, comment: "")
        
        button.addTarget(self, action: #selector(ButtonViewController.buttonClicked(_:)), for: .touchUpInside)
    }
    
    func configureLargeSymbolButton(_ button: UIButton) {
        let buttonImage = UIImage(systemName: "person")
        
        if #available(iOS 15, *) {
            // For iOS 15 use the UIButtonConfiguration to change the size.
            var buttonConfig = UIButton.Configuration.plain()
            buttonConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .largeTitle)
            buttonConfig.image = buttonImage
            button.configuration = buttonConfig
        } else {
            button.setImage(buttonImage, for: .normal)
        }
        
        // Since this button title is just an image, add an accessibility label.
        button.accessibilityLabel = NSLocalizedString("Person", bundle: .module, comment: "")
        
        button.addTarget(self, action: #selector(ButtonViewController.buttonClicked(_:)), for: .touchUpInside)
    }
    
    func configureSymbolTextButton(_ button: UIButton) {
        // Button with image to the left of the title.
        
        let buttonImage = UIImage(systemName: "person")

        if #available(iOS 15, *) {
            // Use UIButtonConfiguration to set the image.
            var buttonConfig = UIButton.Configuration.plain()
            
            // Set up the symbol image size to match that of the title font size.
            buttonConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .body)
            buttonConfig.image = buttonImage
    
            button.configuration = buttonConfig
        } else {
            button.setImage(buttonImage, for: .normal)
            
            // Set up the symbol image size to match that of the title font size.
            let config = UIImage.SymbolConfiguration(textStyle: .body, scale: .small)
            button.setPreferredSymbolConfiguration(config, forImageIn: .normal)
        }
        
        // Set the button's title and font.
        button.setTitle(NSLocalizedString("Person", bundle: .module, comment: ""), for: [])
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)

        button.addTarget(self, action: #selector(ButtonViewController.buttonClicked(_:)), for: .touchUpInside)
    }
    
    func configureTextSymbolButton(_ button: UIButton) {
        // Button with image to the right of the title.
        
        let buttonImage = UIImage(systemName: "person")

        if #available(iOS 15, *) {
            // Use UIButtonConfiguration to set the image.
            var buttonConfig = UIButton.Configuration.plain()
            
            // Set up the symbol image size to match that of the title font size.
            buttonConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .body)

            buttonConfig.image = buttonImage
    
            // Set the image placement to the right of the title.
            /** For image placement to work in Mac Catalyst, use UIBehavioralStyle as ".pad",
                Available in macOS 12 or later (Mac Catalyst 15.0 or later).
                Use this for controls that need to look the same between iOS and macOS.
            */
            if traitCollection.userInterfaceIdiom == .mac {
                button.preferredBehavioralStyle = .pad
            }
            buttonConfig.imagePlacement = .trailing
            
            button.configuration = buttonConfig
        }
        
        // Set the button's title and font.
        button.setTitle(NSLocalizedString("Person", bundle: .module, comment: ""), for: [])
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)

        button.addTarget(self, action: #selector(ButtonViewController.buttonClicked(_:)), for: .touchUpInside)
    }
    
    @available(iOS 15.0, *)
    func configureMultiTitleButton(_ button: UIButton) {
        /** To keep the look the same betwen iOS and macOS:
            For setTitle(.highlighted) to work in Mac Catalyst, use UIBehavioralStyle as ".pad",
            Available in macOS 12 or later (Mac Catalyst 15.0 or later).
            Use this for controls that need to look the same between iOS and macOS.
        */
        if traitCollection.userInterfaceIdiom == .mac {
            button.preferredBehavioralStyle = .pad
        }
        
        button.setTitle(NSLocalizedString("Button", bundle: .module, comment: ""), for: .normal)
        button.setTitle(NSLocalizedString("Pressed", bundle: .module, comment: ""), for: .highlighted)
        
        button.addTarget(self, action: #selector(ButtonViewController.buttonClicked(_:)), for: .touchUpInside)
    }
    
    @available(iOS 15.0, *)
    func configureToggleButton(button: UIButton) {
        button.changesSelectionAsPrimaryAction = true // This makes the button style a "toggle button".
    }
    
    func configureTitleTextButton(_ button: UIButton) {
        // Note: Only for iOS the title's color can be changed.
        button.setTitleColor(UIColor.systemGreen, for: [.normal])
        button.setTitleColor(UIColor.systemRed, for: [.highlighted])
        
        button.addTarget(self, action: #selector(ButtonViewController.buttonClicked(_:)), for: .touchUpInside)
    }
    
    func configureBackgroundButton(_ button: UIButton) {
        if #available(iOS 15, *) {
            /** To keep the look the same betwen iOS and macOS:
                For setBackgroundImage to work in Mac Catalyst, use UIBehavioralStyle as ".pad",
                Available in macOS 12 or later (Mac Catalyst 15.0 or later).
                Use this for controls that need to look the same between iOS and macOS.
            */
            if traitCollection.userInterfaceIdiom == .mac {
                button.preferredBehavioralStyle = .pad
            }
        }

        button.setBackgroundImage(UIImage(named: "background", in: .module, compatibleWith: nil), for: .normal)
        button.setBackgroundImage(UIImage(named: "background_highlighted", in: .module, compatibleWith: nil), for: .highlighted)
        button.setBackgroundImage(UIImage(named: "background_disabled", in: .module, compatibleWith: nil), for: .disabled)

        button.addTarget(self, action: #selector(ButtonViewController.buttonClicked(_:)), for: .touchUpInside)
    }
    
    // This handler is called when this button needs updating.
    @available(iOS 15.0, *)
    func configureUpdateActivityHandlerButton(_ button: UIButton) {
        let activityUpdateHandler: (UIButton) -> Void = { button in
            /// Shows an activity indicator in place of an image. Its placement is controlled by the `imagePlacement` property.

            // Start with the current button's configuration.
            var config = button.configuration
            config?.showsActivityIndicator = button.isSelected ? false : true
            button.configuration = config
        }
                    
        var buttonConfig = UIButton.Configuration.plain()
        buttonConfig.image = UIImage(systemName: "tray")
        buttonConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .body)
        button.configuration = buttonConfig
        
        // Set the button's title and font.
        button.setTitle(NSLocalizedString("Button", bundle: .module, comment: ""), for: [])
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        
        button.changesSelectionAsPrimaryAction = true // This turns on the toggle behavior.
        button.configurationUpdateHandler = activityUpdateHandler
        
        // For this button to include an activity indicator next to the title, keep the iPad behavior.
        if traitCollection.userInterfaceIdiom == .mac {
            button.preferredBehavioralStyle = .pad
        }
          
        button.addTarget(self, action: #selector(ButtonViewController.toggleButtonClicked(_:)), for: .touchUpInside)
    }
    
    @available(iOS 15.0, *)
    func configureUpdateHandlerButton(_ button: UIButton) {
        // This is called when a button needs an update.
        let colorUpdateHandler: (UIButton) -> Void = { button in
            button.configuration?.baseBackgroundColor = button.isSelected
                ? UIColor.systemPink.withAlphaComponent(0.4)
                : UIColor.systemPink
        }
                    
        let buttonConfig = UIButton.Configuration.filled()
        button.configuration = buttonConfig
        
        button.changesSelectionAsPrimaryAction = true // This turns on the toggle behavior.
        button.configurationUpdateHandler = colorUpdateHandler
        
        // For this button to use baseBackgroundColor for the visual toggle state, keep the iPad behavior.
        if traitCollection.userInterfaceIdiom == .mac {
            button.preferredBehavioralStyle = .pad
        }
        
        button.addTarget(self, action: #selector(ButtonViewController.toggleButtonClicked(_:)), for: .touchUpInside)
    }
    
    @available(iOS 15.0, *)
    func configureUpdateImageHandlerButton(_ button: UIButton) {
        // This is called when a button needs an update.
        let colorUpdateHandler: (UIButton) -> Void = { button in
            button.configuration?.image =
                button.isSelected ? UIImage(systemName: "cart.fill") : UIImage(systemName: "cart")
            button.toolTip =
                button.isSelected ?
                    NSLocalizedString("CartFilledButtonToolTipTitle", bundle: .module, comment: "") :
                    NSLocalizedString("CartEmptyButtonToolTipTitle", bundle: .module, comment: "")
        }
        
        var buttonConfig = UIButton.Configuration.plain()
        buttonConfig.image = UIImage(systemName: "cart")
        buttonConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .largeTitle)
        button.configuration = buttonConfig
        
        button.changesSelectionAsPrimaryAction = true // This turns on the toggle behavior.
        button.configurationUpdateHandler = colorUpdateHandler
        
        // For this button to use the updateHandler to change it's icon for the visual toggle state, keep the iPad behavior.
        if traitCollection.userInterfaceIdiom == .mac {
            button.preferredBehavioralStyle = .pad
        }
        
        button.setTitle("", for: []) // No title, just an image.
        button.isSelected = false
        
        button.addTarget(self, action: #selector(ButtonViewController.toggleButtonClicked(_:)), for: .touchUpInside)
    }
    
    // MARK: - Add To Cart Button
    
    @available(iOS 15.0, *)
    func toolTipInteraction(_ interaction: UIToolTipInteraction, configurationAt point: CGPoint) -> UIToolTipConfiguration? {
        let formatString = NSLocalizedString("Cart Tooltip String",
                                             bundle: .module,
                                             comment: "Cart Tooltip String format to be found in Localizable.stringsdict")
        let resultString = String.localizedStringWithFormat(formatString, cartItemCount)
        return UIToolTipConfiguration(toolTip: resultString)
    }
    
    @available(iOS 15.0, *)
    func addToCart(action: UIAction) {
        cartItemCount = cartItemCount > 0 ? 0 : 12
        if let button = action.sender as? UIButton {
            button.setNeedsUpdateConfiguration()
        }
    }
    
    @available(iOS 15.0, *)
    func configureAddToCartButton(_ button: UIButton) {
        var config = UIButton.Configuration.filled()
        config.buttonSize = .large
        config.image = UIImage(systemName: "cart.fill")
        config.title = "Add to Cart"
        config.cornerStyle = .capsule
        config.baseBackgroundColor = UIColor.systemTeal
        button.configuration = config

        button.toolTip = "" // The value will be determined in its delegate.
        button.toolTipInteraction?.delegate = self
        
        button.addAction(UIAction(handler: addToCart(action:)), for: .touchUpInside)
        
        // For this button to include subtitle and larger size, the behavioral style needs to be set to ".pad".
        if traitCollection.userInterfaceIdiom == .mac {
            button.preferredBehavioralStyle = .pad
        }

        button.changesSelectionAsPrimaryAction = true // This turns on the toggle behavior.
        
        // This handler is called when this button needs updating.
        button.configurationUpdateHandler = {
            [unowned self] button in
            
            // Start with the current button's configuration.
            var newConfig = button.configuration
            
            if button.isSelected {
                // The button was clicked or tapped.
                newConfig?.image = cartItemCount > 0
                    ? UIImage(systemName: "cart.fill.badge.plus")
                    : UIImage(systemName: "cart.badge.plus")
                
                let formatString = NSLocalizedString("Cart Items String",
                                                     bundle: .module,
                                                     comment: "Cart Items String format to be found in Localizable.stringsdict")
                let resultString = String.localizedStringWithFormat(formatString, cartItemCount)
                newConfig?.subtitle = resultString
            } else {
                // As the button is highlighted (pressed), apply a temporary image and subtitle.
                newConfig?.image = UIImage(systemName: "cart.fill")
                newConfig?.subtitle = ""
            }

            newConfig?.imagePadding = 8 // Add a litle more space between the icon and button title.
            
            // Note: To change the padding between the title and subtitle, set "titlePadding".
            // Note: To change the padding around the perimeter of the button, set "contentInsets".
            
            button.configuration = newConfig
        }
    }
    
    // MARK: - Button Actions

    @objc
    func buttonClicked(_ sender: UIButton) {
        Swift.debugPrint("Button was clicked.")
    }
    
    @objc
    func toggleButtonClicked(_ sender: UIButton) {
        Swift.debugPrint("Toggle action: \(sender)")
    }
    
}
