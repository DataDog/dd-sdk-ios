/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that demonstrates how to use `UISwitch`.
*/

import UIKit

class SwitchViewController: BaseTableViewController {

    // Cell identifier for each switch table view cell.
    enum SwitchKind: String, CaseIterable {
        case defaultSwitch
        case checkBoxSwitch
        case tintedSwitch
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        testCells.append(contentsOf: [
            CaseElement(title: NSLocalizedString("DefaultSwitchTitle", bundle: .module, comment: ""),
                        cellID: SwitchKind.defaultSwitch.rawValue,
                        configHandler: configureDefaultSwitch)
        ])
        
        // Checkbox switch is available only when running on macOS.
        if navigationController!.traitCollection.userInterfaceIdiom == .mac {
            testCells.append(contentsOf: [
                CaseElement(title: NSLocalizedString("CheckboxSwitchTitle", bundle: .module, comment: ""),
                            cellID: SwitchKind.checkBoxSwitch.rawValue,
                            configHandler: configureCheckboxSwitch)
            ])
        }
        
        // Tinted switch is available only when running on iOS.
        if navigationController!.traitCollection.userInterfaceIdiom != .mac {
            testCells.append(contentsOf: [
                CaseElement(title: NSLocalizedString("TintedSwitchTitle", bundle: .module, comment: ""),
                            cellID: SwitchKind.tintedSwitch.rawValue,
                            configHandler: configureTintedSwitch)
            ])
        }
    }

    // MARK: - Configuration
    
    func configureDefaultSwitch(_ switchControl: UISwitch) {
        switchControl.setOn(true, animated: false)
        switchControl.preferredStyle = .sliding
        
        switchControl.addTarget(self,
                                action: #selector(SwitchViewController.switchValueDidChange(_:)),
                                for: .valueChanged)
    }
    
    func configureCheckboxSwitch(_ switchControl: UISwitch) {
        switchControl.setOn(true, animated: false)

        switchControl.addTarget(self,
                                 action: #selector(SwitchViewController.switchValueDidChange(_:)),
                                 for: .valueChanged)
        
        // On the Mac, make sure this control take on the apperance of a checkbox with a title.
        if traitCollection.userInterfaceIdiom == .mac {
            switchControl.preferredStyle = .checkbox
            
            // Title on a UISwitch is only supported when running Catalyst apps in the Mac Idiom.
            switchControl.title = NSLocalizedString("SwitchTitle", bundle: .module, comment: "")
        }
    }

    func configureTintedSwitch(_ switchControl: UISwitch) {
        switchControl.tintColor = UIColor.systemBlue
        switchControl.onTintColor = UIColor.systemGreen
        switchControl.thumbTintColor = UIColor.systemPurple

        switchControl.addTarget(self,
                               action: #selector(SwitchViewController.switchValueDidChange(_:)),
                               for: .valueChanged)
    }
    
    // MARK: - Actions

    @objc
    func switchValueDidChange(_ aSwitch: UISwitch) {
        Swift.debugPrint("A switch changed its value: \(aSwitch.isOn).")
    }
    
}
