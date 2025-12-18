/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that demonstrates how to use `UISlider`.
*/

import UIKit

class SliderViewController: BaseTableViewController {
    // Cell identifier for each slider table view cell.
    enum SliderKind: String, CaseIterable {
        case sliderDefault
        case sliderTinted
        case sliderCustom
        case sliderMaxMinImage
    }

    // MARK: - View Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()

        testCells.append(contentsOf: [
            CaseElement(title: NSLocalizedString("DefaultTitle", bundle: .module, comment: ""),
                        cellID: SliderKind.sliderDefault.rawValue,
                        configHandler: configureDefaultSlider)
        ])
        
        if #available(iOS 15, *) {
            // These cases require iOS 15 or later when running on Mac Catalyst.
            testCells.append(contentsOf: [
                CaseElement(title: NSLocalizedString("CustomTitle", bundle: .module, comment: ""),
                            cellID: SliderKind.sliderCustom.rawValue,
                            configHandler: configureCustomSlider)
            ])
            testCells.append(contentsOf: [
                CaseElement(title: NSLocalizedString("MinMaxImagesTitle", bundle: .module, comment: ""),
                            cellID: SliderKind.sliderMaxMinImage.rawValue,
                            configHandler: configureMinMaxImageSlider)
            ])
            testCells.append(contentsOf: [
                CaseElement(title: NSLocalizedString("TintedTitle", bundle: .module, comment: ""),
                            cellID: SliderKind.sliderTinted.rawValue,
                            configHandler: configureTintedSlider)
            ])
        }
    }

    // MARK: - Configuration

    func configureDefaultSlider(_ slider: UISlider) {
        slider.minimumValue = 0
        slider.maximumValue = 100
        slider.value = 42
        slider.isContinuous = true

        slider.addTarget(self, action: #selector(SliderViewController.sliderValueDidChange(_:)), for: .valueChanged)
    }

    @available(iOS 15.0, *)
    func configureTintedSlider(slider: UISlider) {
        /** To keep the look the same betwen iOS and macOS:
            For minimumTrackTintColor, maximumTrackTintColor to work in Mac Catalyst, use UIBehavioralStyle as ".pad",
            Available in macOS 12 or later (Mac Catalyst 15.0 or later).
            Use this for controls that need to look the same between iOS and macOS.
        */
        if traitCollection.userInterfaceIdiom == .mac {
            slider.preferredBehavioralStyle = .pad
        }

        slider.minimumTrackTintColor = UIColor.systemBlue
        slider.maximumTrackTintColor = UIColor.systemPurple
        
        slider.addTarget(self, action: #selector(SliderViewController.sliderValueDidChange(_:)), for: .valueChanged)
    }

    @available(iOS 15.0, *)
    func configureCustomSlider(slider: UISlider) {
        /** To keep the look the same betwen iOS and macOS:
            For setMinimumTrackImage, setMaximumTrackImage, setThumbImage to work in Mac Catalyst, use UIBehavioralStyle as ".pad",
            Available in macOS 12 or later (Mac Catalyst 15.0 or later).
            Use this for controls that need to look the same between iOS and macOS.
        */
        if traitCollection.userInterfaceIdiom == .mac {
            slider.preferredBehavioralStyle = .pad
        }
        
        let leftTrackImage = UIImage(named: "slider_blue_track", in: .module, compatibleWith: nil)
        slider.setMinimumTrackImage(leftTrackImage, for: .normal)

        let rightTrackImage = UIImage(named: "slider_green_track", in: .module, compatibleWith: nil)
        slider.setMaximumTrackImage(rightTrackImage, for: .normal)

        // Set the sliding thumb image (normal and highlighted).
        //
        // For fun, choose a different image symbol configuration for the thumb's image between macOS and iOS.
        var thumbImageConfig: UIImage.SymbolConfiguration
        if slider.traitCollection.userInterfaceIdiom == .mac {
            thumbImageConfig = UIImage.SymbolConfiguration(scale: .large)
        } else {
            thumbImageConfig = UIImage.SymbolConfiguration(pointSize: 30, weight: .heavy, scale: .large)
        }
        let thumbImage = UIImage(systemName: "circle.fill", withConfiguration: thumbImageConfig)
        slider.setThumbImage(thumbImage, for: .normal)
        
        let thumbImageHighlighted = UIImage(systemName: "circle", withConfiguration: thumbImageConfig)
        slider.setThumbImage(thumbImageHighlighted, for: .highlighted)

        // Set the rest of the slider's attributes.
        slider.minimumValue = 0
        slider.maximumValue = 100
        slider.isContinuous = false
        slider.value = 84

        slider.addTarget(self, action: #selector(SliderViewController.sliderValueDidChange(_:)), for: .valueChanged)
    }
    
    func configureMinMaxImageSlider(slider: UISlider) {
        /** To keep the look the same betwen iOS and macOS:
            For setMinimumValueImage, setMaximumValueImage to work in Mac Catalyst, use UIBehavioralStyle as ".pad",
            Available in macOS 12 or later (Mac Catalyst 15.0 or later).
            Use this for controls that need to look the same between iOS and macOS.
        */
        if #available(iOS 15, *) {
            if traitCollection.userInterfaceIdiom == .mac {
                slider.preferredBehavioralStyle = .pad
            }
        }
        
        slider.minimumValueImage = UIImage(systemName: "tortoise")
        slider.maximumValueImage = UIImage(systemName: "hare")
        
        slider.addTarget(self, action: #selector(SliderViewController.sliderValueDidChange(_:)), for: .valueChanged)
    }
    
    // MARK: - Actions

    @objc
    func sliderValueDidChange(_ slider: UISlider) {
        let formattedValue = String(format: "%.2f", slider.value)
        Swift.debugPrint("Slider changed its value: \(formattedValue)")
    }

}
