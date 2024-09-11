/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that demonstrates how to attach menus to `UIButton`.
*/

import UIKit

class MenuButtonViewController: BaseTableViewController {
    
    // Cell identifier for each menu button table view cell.
    enum MenuButtonKind: String, CaseIterable {
        case buttonMenuProgrammatic
        case buttonMenuMultiAction
        case buttonSubMenu
        case buttonMenuSelection
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        testCells.append(contentsOf: [
            CaseElement(title: NSLocalizedString("DropDownProgTitle", bundle: .module, comment: ""),
                        cellID: MenuButtonKind.buttonMenuProgrammatic.rawValue,
                        configHandler: configureDropDownProgrammaticButton),
            CaseElement(title: NSLocalizedString("DropDownMultiActionTitle", bundle: .module, comment: ""),
                        cellID: MenuButtonKind.buttonMenuMultiAction.rawValue,
                        configHandler: configureDropdownMultiActionButton),
            CaseElement(title: NSLocalizedString("DropDownButtonSubMenuTitle", bundle: .module, comment: ""),
                        cellID: MenuButtonKind.buttonSubMenu.rawValue,
                        configHandler: configureDropdownSubMenuButton),
            CaseElement(title: NSLocalizedString("PopupSelection", bundle: .module, comment: ""),
                        cellID: MenuButtonKind.buttonMenuSelection.rawValue,
                        configHandler: configureSelectionPopupButton)
        ])
    }

    // MARK: - Handlers
    
    enum ButtonMenuActionIdentifiers: String {
        case item1
        case item2
        case item3
    }
    func menuHandler(action: UIAction) {
        switch action.identifier.rawValue {
        case ButtonMenuActionIdentifiers.item1.rawValue:
            Swift.debugPrint("Menu Action: item 1")
        case ButtonMenuActionIdentifiers.item2.rawValue:
            Swift.debugPrint("Menu Action: item 2")
        case ButtonMenuActionIdentifiers.item3.rawValue:
            Swift.debugPrint("Menu Action: item 3")
        default: break
        }
    }
    
    func item4Handler(action: UIAction) {
        Swift.debugPrint("Menu Action: \(action.title)")
    }
    
    // MARK: - Drop Down Menu Buttons
    
    func configureDropDownProgrammaticButton(button: UIButton) {
        button.menu = UIMenu(children: [
            UIAction(title: String(format: NSLocalizedString("ItemTitle", bundle: .module, comment: ""), "1"),
                     identifier: UIAction.Identifier(ButtonMenuActionIdentifiers.item1.rawValue),
                     handler: menuHandler),
            UIAction(title: String(format: NSLocalizedString("ItemTitle", bundle: .module, comment: ""), "2"),
                     identifier: UIAction.Identifier(ButtonMenuActionIdentifiers.item2.rawValue),
                     handler: menuHandler)
        ])
        
        button.showsMenuAsPrimaryAction = true
    }
    
    func configureDropdownMultiActionButton(button: UIButton) {
        let buttonMenu = UIMenu(children: [
            // Share a single handler for the first 3 actions.
            UIAction(title: String(format: NSLocalizedString("ItemTitle", bundle: .module, comment: ""), "1"),
                     image: UIImage(systemName: "1.circle"),
                     identifier: UIAction.Identifier(ButtonMenuActionIdentifiers.item1.rawValue),
                     attributes: [],
                     handler: menuHandler),
            UIAction(title: String(format: NSLocalizedString("ItemTitle", bundle: .module, comment: ""), "2"),
                     image: UIImage(systemName: "2.circle"),
                     identifier: UIAction.Identifier(ButtonMenuActionIdentifiers.item2.rawValue),
                     handler: menuHandler),
            UIAction(title: String(format: NSLocalizedString("ItemTitle", bundle: .module, comment: ""), "3"),
                     image: UIImage(systemName: "3.circle"),
                     identifier: UIAction.Identifier(ButtonMenuActionIdentifiers.item3.rawValue),
                     handler: menuHandler),
            
            // Use a separate handler for this 4th action.
            UIAction(title: String(format: NSLocalizedString("ItemTitle", bundle: .module, comment: ""), "4"),
                     image: UIImage(systemName: "4.circle"),
                     identifier: nil,
                     handler: item4Handler(action:)),
            
            // Use a closure for the 5th action.
            UIAction(title: String(format: NSLocalizedString("ItemTitle", bundle: .module, comment: ""), "5"),
                     image: UIImage(systemName: "5.circle"),
                     identifier: nil) { action in
                Swift.debugPrint("Menu Action: \(action.title)")
            },
            
            // Use attributes to make the 6th action disabled.
            UIAction(title: String(format: NSLocalizedString("ItemTitle", bundle: .module, comment: ""), "6"),
                     image: UIImage(systemName: "6.circle"),
                     identifier: nil,
                     attributes: [UIMenuElement.Attributes.disabled]) { action in
                 Swift.debugPrint("Menu Action: \(action.title)")
            }
        ])
        button.menu = buttonMenu
        
        // This makes the button behave like a drop down menu.
        button.showsMenuAsPrimaryAction = true
    }

    func configureDropdownSubMenuButton(button: UIButton) {
        let sortClosure = { (action: UIAction) in
            Swift.debugPrint("Sort by: \(action.title)")
        }
        let refreshClosure = { (action: UIAction) in
            Swift.debugPrint("Refresh handler")
        }
        let accountHandler = { (action: UIAction) in
            Swift.debugPrint("Account handler")
        }
        
        var sortMenu: UIMenu
        if #available(iOS 15, *) { // .singleSelection option only on iOS 15 or later
            // The sort sub menu supports a selection.
            sortMenu = UIMenu(title: "Sort By", options: .singleSelection, children: [
                UIAction(title: "Date", state: .on, handler: sortClosure),
                UIAction(title: "Size", handler: sortClosure)
            ])
        } else {
            sortMenu = UIMenu(title: "Sort By", children: [
                UIAction(title: "Date", handler: sortClosure),
                UIAction(title: "Size", handler: sortClosure)
            ])
        }
        
        let topMenu = UIMenu(children: [
            UIAction(title: "Refresh", handler: refreshClosure),
            UIAction(title: "Account", handler: accountHandler),
            sortMenu
        ])
        
        // This makes the button behave like a drop down menu.
        button.showsMenuAsPrimaryAction = true
        button.menu = topMenu
    }
    
    // MARK: - Selection Popup Menu Button
     
    func updateColor(_ title: String) {
        Swift.debugPrint("Color selected: \(title)")
    }
    
    func configureSelectionPopupButton(button: UIButton) {
        let colorClosure = { [unowned self] (action: UIAction) in
            self.updateColor(action.title)
        }
        
        button.menu = UIMenu(children: [
            UIAction(title: "Red", handler: colorClosure),
            UIAction(title: "Green", state: .on, handler: colorClosure), // The default selected item (green).
            UIAction(title: "Blue", handler: colorClosure)
        ])
        
        // This makes the button behave like a drop down menu.
        button.showsMenuAsPrimaryAction = true

        if #available(iOS 15, *) {
            button.changesSelectionAsPrimaryAction = true
            // Select the default menu item (green).
            updateColor((button.menu?.selectedElements.first!.title)!)
        }
    }
    
}
