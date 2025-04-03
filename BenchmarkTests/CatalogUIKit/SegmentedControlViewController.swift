/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that demonstrates how to use `UISegmentedControl`.
*/

import UIKit

class SegmentedControlViewController: BaseTableViewController {
    
    // Cell identifier for each segmented control table view cell.
    enum SegmentKind: String, CaseIterable {
        case segmentDefault
        case segmentTinted
        case segmentCustom
        case segmentCustomBackground
        case segmentAction
    }
    
    // MARK: - View Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        testCells.append(contentsOf: [
            CaseElement(title: NSLocalizedString("DefaultTitle", bundle: .module, comment: ""),
                        cellID: SegmentKind.segmentDefault.rawValue,
                        configHandler: configureDefaultSegmentedControl),
            CaseElement(title: NSLocalizedString("CustomSegmentsTitle", bundle: .module, comment: ""),
                        cellID: SegmentKind.segmentCustom.rawValue,
                        configHandler: configureCustomSegmentsSegmentedControl),
            CaseElement(title: NSLocalizedString("CustomBackgroundTitle", bundle: .module, comment: ""),
                        cellID: SegmentKind.segmentCustomBackground.rawValue,
                        configHandler: configureCustomBackgroundSegmentedControl),
            CaseElement(title: NSLocalizedString("ActionBasedTitle", bundle: .module, comment: ""),
                        cellID: SegmentKind.segmentAction.rawValue,
                        configHandler: configureActionBasedSegmentedControl)
        ])
        if self.traitCollection.userInterfaceIdiom != .mac {
            // Tinted segmented control is only available on iOS.
            testCells.append(contentsOf: [
                CaseElement(title: "Tinted",
                            cellID: SegmentKind.segmentTinted.rawValue,
                            configHandler: configureTintedSegmentedControl)
            ])
        }
    }

    // MARK: - Configuration

    func configureDefaultSegmentedControl(_ segmentedControl: UISegmentedControl) {
        // As a demonstration, disable the first segment.
        segmentedControl.setEnabled(false, forSegmentAt: 0)

        segmentedControl.addTarget(self, action: #selector(SegmentedControlViewController.selectedSegmentDidChange(_:)), for: .valueChanged)
    }

    func configureTintedSegmentedControl(_ segmentedControl: UISegmentedControl) {
        // Use a dynamic tinted "green" color (separate one for Light Appearance and separate one for Dark Appearance).
        segmentedControl.selectedSegmentTintColor = UIColor(named: "tinted_segmented_control", in: .module, compatibleWith: nil)!
        segmentedControl.selectedSegmentIndex = 1

        segmentedControl.addTarget(self, action: #selector(SegmentedControlViewController.selectedSegmentDidChange(_:)), for: .valueChanged)
    }
    
    func configureCustomSegmentsSegmentedControl(_ segmentedControl: UISegmentedControl) {
        let airplaneImage = UIImage(systemName: "airplane")
        airplaneImage?.accessibilityLabel = NSLocalizedString("Airplane", bundle: .module, comment: "")
        segmentedControl.setImage(airplaneImage, forSegmentAt: 0)
        
        let giftImage = UIImage(systemName: "gift")
        giftImage?.accessibilityLabel = NSLocalizedString("Gift", bundle: .module, comment: "")
        segmentedControl.setImage(giftImage, forSegmentAt: 1)
        
        let burstImage = UIImage(systemName: "burst")
        burstImage?.accessibilityLabel = NSLocalizedString("Burst", bundle: .module, comment: "")
        segmentedControl.setImage(burstImage, forSegmentAt: 2)
        
        segmentedControl.selectedSegmentIndex = 0

        segmentedControl.addTarget(self, action: #selector(SegmentedControlViewController.selectedSegmentDidChange(_:)), for: .valueChanged)
    }
    
    // Utility function to resize an image to a particular size.
    func scaledImage(_ image: UIImage, scaledToSize newSize: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        image.draw(in: CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return newImage
    }
    
    // Configure the segmented control with a background image, dividers, and custom font.
    // The background image first needs to be sized to match the control's size.
    //
    func configureCustomBackgroundSegmentedControl(_ placeHolderView: UIView) {
        let customBackgroundSegmentedControl =
            UISegmentedControl(items: [NSLocalizedString("CheckTitle", bundle: .module, comment: ""),
                                       NSLocalizedString("SearchTitle", bundle: .module, comment: ""),
                                       NSLocalizedString("ToolsTitle", bundle: .module, comment: "")])
        customBackgroundSegmentedControl.selectedSegmentIndex = 2
        
        // Place this custom segmented control within the placeholder view.
        customBackgroundSegmentedControl.frame.size.width = placeHolderView.frame.size.width
        customBackgroundSegmentedControl.frame.origin.y =
            (placeHolderView.bounds.size.height - customBackgroundSegmentedControl.bounds.size.height) / 2
        placeHolderView.addSubview(customBackgroundSegmentedControl)
    
        // Set the background images for each control state.
        let normalSegmentBackgroundImage = UIImage(named: "background", in: .module, compatibleWith: nil)
        // Size the background image to match the bounds of the segmented control.
        let backgroundImageSize = customBackgroundSegmentedControl.bounds.size
        let newBackgroundImageSize = scaledImage(normalSegmentBackgroundImage!, scaledToSize: backgroundImageSize)
        customBackgroundSegmentedControl.setBackgroundImage(newBackgroundImageSize, for: .normal, barMetrics: .default)
        
        let disabledSegmentBackgroundImage = UIImage(named: "background_disabled", in: .module, compatibleWith: nil)
        customBackgroundSegmentedControl.setBackgroundImage(disabledSegmentBackgroundImage, for: .disabled, barMetrics: .default)

        let highlightedSegmentBackgroundImage = UIImage(named: "background_highlighted", in: .module, compatibleWith: nil)
        customBackgroundSegmentedControl.setBackgroundImage(highlightedSegmentBackgroundImage, for: .highlighted, barMetrics: .default)

        // Set the divider image.
        let segmentDividerImage = UIImage(named: "stepper_and_segment_divider", in: .module, compatibleWith: nil)
        customBackgroundSegmentedControl.setDividerImage(segmentDividerImage,
                                                         forLeftSegmentState: .normal,
                                                         rightSegmentState: .normal,
                                                         barMetrics: .default)

        // Create a font to use for the attributed title, for both normal and highlighted states.
        let font = UIFont(descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body), size: 0)
        let normalTextAttributes = [
            NSAttributedString.Key.foregroundColor: UIColor.systemPurple,
            NSAttributedString.Key.font: font
        ]
        customBackgroundSegmentedControl.setTitleTextAttributes(normalTextAttributes, for: .normal)

        let highlightedTextAttributes = [
            NSAttributedString.Key.foregroundColor: UIColor.systemGreen,
            NSAttributedString.Key.font: font
        ]
        customBackgroundSegmentedControl.setTitleTextAttributes(highlightedTextAttributes, for: .highlighted)

        customBackgroundSegmentedControl.addTarget(self,
                                                   action: #selector(SegmentedControlViewController.selectedSegmentDidChange(_:)),
                                                   for: .valueChanged)
    }

    func configureActionBasedSegmentedControl(_ segmentedControl: UISegmentedControl) {
        segmentedControl.selectedSegmentIndex = 0
        let firstAction =
            UIAction(title: NSLocalizedString("CheckTitle", bundle: .module, comment: "")) { action in
                Swift.debugPrint("Segment Action '\(action.title)'")
            }
        segmentedControl.setAction(firstAction, forSegmentAt: 0)
        let secondAction =
            UIAction(title: NSLocalizedString("SearchTitle", bundle: .module, comment: "")) { action in
                Swift.debugPrint("Segment Action '\(action.title)'")
            }
        segmentedControl.setAction(secondAction, forSegmentAt: 1)
        let thirdAction =
            UIAction(title: NSLocalizedString("ToolsTitle", bundle: .module, comment: "")) { action in
                Swift.debugPrint("Segment Action '\(action.title)'")
            }
        segmentedControl.setAction(thirdAction, forSegmentAt: 2)
    }
    
    // MARK: - Actions

    @objc
    func selectedSegmentDidChange(_ segmentedControl: UISegmentedControl) {
        Swift.debugPrint("The selected segment: \(segmentedControl.selectedSegmentIndex).")
    }
    
    // MARK: - UITableViewDataSource
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellTest = testCells[indexPath.section]
        let cell = tableView.dequeueReusableCell(withIdentifier: cellTest.cellID, for: indexPath)
        if let segementedControl = cellTest.targetView(cell) as? UISegmentedControl {
            cellTest.configHandler(segementedControl)
        } else if let placeHolderView = cellTest.targetView(cell) {
            // The only non-segmented control cell has a placeholder UIView (for adding one as a subview).
            cellTest.configHandler(placeHolderView)
        }
        return cell
    }

}
