/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A simple outline view for the sample app's main UI
*/

import UIKit

class OutlineViewController: UIViewController {

    enum Section {
        case main
    }

    class OutlineItem: Identifiable, Hashable {
        let title: String
        let subitems: [OutlineItem]
        let storyboardName: String?
        let imageName: String?

        init(title: String, imageName: String?, storyboardName: String? = nil, subitems: [OutlineItem] = []) {
            self.title = title
            self.subitems = subitems
            self.storyboardName = storyboardName
            self.imageName = imageName
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        static func == (lhs: OutlineItem, rhs: OutlineItem) -> Bool {
            return lhs.id == rhs.id
        }

    }

    var dataSource: UICollectionViewDiffableDataSource<Section, OutlineItem>! = nil
    var outlineCollectionView: UICollectionView! = nil

    private var detailTargetChangeObserver: Any? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()

        configureCollectionView()
        configureDataSource()
        
        // Add a translucent background to the primary view controller for the Mac.
        splitViewController!.primaryBackgroundStyle = .sidebar
        view.backgroundColor = UIColor.clear
          
        // Listen for when the split view controller is expanded or collapsed for iPad multi-tasking,
        // and on device rotate (iPhones that support regular size class).
        detailTargetChangeObserver =
            NotificationCenter.default.addObserver(forName: UIViewController.showDetailTargetDidChangeNotification,
                                                   object: nil,
                                                   queue: OperationQueue.main,
                                                   using: { _ in
                // Posted when a split view controller is expanded or collapsed.
                                                                        
                // Re-load the data source, the disclosure indicators need to change (push vs. present on a cell).
                var snapshot = self.dataSource.snapshot()
                snapshot.reloadItems(self.menuItems)
                self.dataSource.apply(snapshot, animatingDifferences: false)
            })
        
        if navigationController!.traitCollection.userInterfaceIdiom == .mac {
            navigationController!.navigationBar.isHidden = true
        }
    }
    
    deinit {
        if let observer = detailTargetChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    lazy var controlsOutlineItem: OutlineItem = {
        
        // Determine the content of the UIButton grouping.
        var buttonItems = [
            OutlineItem(title: NSLocalizedString("ButtonsTitle", bundle: .module, comment: ""), imageName: "rectangle",
                        storyboardName: "ButtonViewController"),
            OutlineItem(title: NSLocalizedString("MenuButtonsTitle", bundle: .module, comment: ""), imageName: "list.bullet.rectangle",
                        storyboardName: "MenuButtonViewController")
        ]
        // UIPointerInteraction to UIButtons is applied for iPad.
        if navigationController!.traitCollection.userInterfaceIdiom == .pad {
            buttonItems.append(contentsOf:
                [OutlineItem(title: NSLocalizedString("PointerInteractionButtonsTitle", bundle: .module, comment: ""),
                             imageName: "cursorarrow.rays",
                             storyboardName: "PointerInteractionButtonViewController") ])
        }
    
        var controlsSubItems = [
            OutlineItem(title: NSLocalizedString("ButtonsTitle", bundle: .module, comment: ""), imageName: "rectangle.on.rectangle", subitems: buttonItems),
            
            OutlineItem(title: NSLocalizedString("PageControlTitle", bundle: .module, comment: ""), imageName: "photo.on.rectangle", subitems: [
                OutlineItem(title: NSLocalizedString("DefaultPageControlTitle", bundle: .module, comment: ""), imageName: nil,
                            storyboardName: "DefaultPageControlViewController"),
                OutlineItem(title: NSLocalizedString("CustomPageControlTitle", bundle: .module, comment: ""), imageName: nil,
                            storyboardName: "CustomPageControlViewController")
            ]),
            
            OutlineItem(title: NSLocalizedString("SearchBarsTitle", bundle: .module, comment: ""), imageName: "magnifyingglass", subitems: [
                OutlineItem(title: NSLocalizedString("DefaultSearchBarTitle", bundle: .module, comment: ""), imageName: nil,
                            storyboardName: "DefaultSearchBarViewController"),
                OutlineItem(title: NSLocalizedString("CustomSearchBarTitle", bundle: .module, comment: ""), imageName: nil,
                            storyboardName: "CustomSearchBarViewController")
            ]),
            
            OutlineItem(title: NSLocalizedString("SegmentedControlsTitle", bundle: .module, comment: ""), imageName: "square.split.3x1",
                        storyboardName: "SegmentedControlViewController"),
            OutlineItem(title: NSLocalizedString("SlidersTitle", bundle: .module, comment: ""), imageName: nil,
                        storyboardName: "SliderViewController"),
            OutlineItem(title: NSLocalizedString("SwitchesTitle", bundle: .module, comment: ""), imageName: nil,
                        storyboardName: "SwitchViewController"),
            OutlineItem(title: NSLocalizedString("TextFieldsTitle", bundle: .module, comment: ""), imageName: nil,
                        storyboardName: "TextFieldViewController")
        ]
        
        if traitCollection.userInterfaceIdiom != .mac {
            // UIStepper class is not supported when running Mac Catalyst apps in the Mac idiom.
            let stepperItem =
                OutlineItem(title: NSLocalizedString("SteppersTitle", bundle: .module, comment: ""), imageName: nil, storyboardName: "StepperViewController")
            controlsSubItems.append(stepperItem)
        }
        
        return OutlineItem(title: "Controls", imageName: "slider.horizontal.3", subitems: controlsSubItems)
    }()
    
    lazy var pickersOutlineItem: OutlineItem = {
        var pickerSubItems = [
            OutlineItem(title: NSLocalizedString("DatePickerTitle", bundle: .module, comment: ""), imageName: nil,
                        storyboardName: "DatePickerController"),
            OutlineItem(title: NSLocalizedString("ColorPickerTitle", bundle: .module, comment: ""), imageName: nil,
                        storyboardName: "ColorPickerViewController"),
            OutlineItem(title: NSLocalizedString("FontPickerTitle", bundle: .module, comment: ""), imageName: nil,
                        storyboardName: "FontPickerViewController"),
            OutlineItem(title: NSLocalizedString("ImagePickerTitle", bundle: .module, comment: ""), imageName: nil,
                        storyboardName: "ImagePickerViewController")
        ]
        
        if traitCollection.userInterfaceIdiom != .mac {
            // UIPickerView class is not supported when running Mac Catalyst apps in the Mac idiom.
            // To use a picker in macOS, use UIButton with changesSelectionAsPrimaryAction set to "true".
            let pickerViewItem =
                OutlineItem(title: NSLocalizedString("PickerViewTitle", bundle: .module, comment: ""), imageName: nil, storyboardName: "PickerViewController")
            pickerSubItems.append(pickerViewItem)
        }
        
        return OutlineItem(title: "Pickers", imageName: "list.bullet", subitems: pickerSubItems)
    }()
    
    lazy var viewsOutlineItem: OutlineItem = {
        OutlineItem(title: "Views", imageName: "rectangle.stack.person.crop", subitems: [
            OutlineItem(title: NSLocalizedString("ActivityIndicatorsTitle", bundle: .module, comment: ""), imageName: nil,
                        storyboardName: "ActivityIndicatorViewController"),
            OutlineItem(title: NSLocalizedString("AlertControllersTitle", bundle: .module, comment: ""), imageName: nil,
                        storyboardName: "AlertControllerViewController"),
            OutlineItem(title: NSLocalizedString("TextViewTitle", bundle: .module, comment: ""), imageName: nil,
                        storyboardName: "TextViewController"),
            
            OutlineItem(title: NSLocalizedString("ImagesTitle", bundle: .module, comment: ""), imageName: "photo", subitems: [
                OutlineItem(title: NSLocalizedString("ImageViewTitle", bundle: .module, comment: ""), imageName: nil,
                            storyboardName: "ImageViewController"),
                OutlineItem(title: NSLocalizedString("SymbolsTitle", bundle: .module, comment: ""), imageName: nil,
                            storyboardName: "SymbolViewController")
            ]),
            
            OutlineItem(title: NSLocalizedString("ProgressViewsTitle", bundle: .module, comment: ""), imageName: nil,
                        storyboardName: "ProgressViewController"),
            OutlineItem(title: NSLocalizedString("StackViewsTitle", bundle: .module, comment: ""), imageName: nil,
                        storyboardName: "StackViewController"),
            
            OutlineItem(title: NSLocalizedString("ToolbarsTitle", bundle: .module, comment: ""), imageName: "hammer", subitems: [
                OutlineItem(title: NSLocalizedString("DefaultToolBarTitle", bundle: .module, comment: ""), imageName: nil,
                            storyboardName: "DefaultToolbarViewController"),
                OutlineItem(title: NSLocalizedString("TintedToolbarTitle", bundle: .module, comment: ""), imageName: nil,
                            storyboardName: "TintedToolbarViewController"),
                OutlineItem(title: NSLocalizedString("CustomToolbarBarTitle", bundle: .module, comment: ""), imageName: nil,
                            storyboardName: "CustomToolbarViewController")
            ]),
            
            OutlineItem(title: NSLocalizedString("VisualEffectTitle", bundle: .module, comment: ""), imageName: nil, storyboardName: "VisualEffectViewController"),
            
            OutlineItem(title: NSLocalizedString("WebViewTitle", bundle: .module, comment: ""), imageName: nil, storyboardName: "WebViewController")
        ])
    }()
    
    private lazy var menuItems: [OutlineItem] = {
        return [
            controlsOutlineItem,
            viewsOutlineItem,
            pickersOutlineItem
        ]
    }()

}

// MARK: - UICollectionViewDiffableDataSource

extension OutlineViewController {

    private func configureCollectionView() {
        let collectionView =
            UICollectionView(frame: view.bounds, collectionViewLayout: generateLayout())
        view.addSubview(collectionView)
        collectionView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        self.outlineCollectionView = collectionView
        collectionView.delegate = self
    }

    private func configureDataSource() {

        let containerCellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, OutlineItem> { (cell, indexPath, menuItem) in

            var contentConfiguration = cell.defaultContentConfiguration()
            contentConfiguration.text = menuItem.title
           
            if let image = menuItem.imageName {
                contentConfiguration.image = UIImage(systemName: image)
            }
            
            contentConfiguration.textProperties.font = .preferredFont(forTextStyle: .headline)
            cell.contentConfiguration = contentConfiguration
            
            let disclosureOptions = UICellAccessory.OutlineDisclosureOptions(style: .header)
            cell.accessories = [.outlineDisclosure(options: disclosureOptions)]
            
            let background = UIBackgroundConfiguration.clear()
            cell.backgroundConfiguration = background
        }
        
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, OutlineItem> { cell, indexPath, menuItem in
            var contentConfiguration = cell.defaultContentConfiguration()
            contentConfiguration.text = menuItem.title
            
            if let image = menuItem.imageName {
                contentConfiguration.image = UIImage(systemName: image)
            }
            
            cell.contentConfiguration = contentConfiguration
            
            let background = UIBackgroundConfiguration.clear()
            cell.backgroundConfiguration = background
            
            cell.accessories = self.splitViewWantsToShowDetail() ? [] : [.disclosureIndicator()]
        }
        
        dataSource = UICollectionViewDiffableDataSource<Section, OutlineItem>(collectionView: outlineCollectionView) {
            (collectionView: UICollectionView, indexPath: IndexPath, item: OutlineItem) -> UICollectionViewCell? in
            // Return the cell.
            if item.subitems.isEmpty {
                return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
            } else {
                return collectionView.dequeueConfiguredReusableCell(using: containerCellRegistration, for: indexPath, item: item)
            }
        }

        // Load our initial data.
        let snapshot = initialSnapshot()
        self.dataSource.apply(snapshot, to: .main, animatingDifferences: false)
    }

    private func generateLayout() -> UICollectionViewLayout {
        let listConfiguration = UICollectionLayoutListConfiguration(appearance: .sidebar)
        let layout = UICollectionViewCompositionalLayout.list(using: listConfiguration)
        return layout
    }

    private func initialSnapshot() -> NSDiffableDataSourceSectionSnapshot<OutlineItem> {
        var snapshot = NSDiffableDataSourceSectionSnapshot<OutlineItem>()

        func addItems(_ menuItems: [OutlineItem], to parent: OutlineItem?) {
            snapshot.append(menuItems, to: parent)
            for menuItem in menuItems where !menuItem.subitems.isEmpty {
                addItems(menuItem.subitems, to: menuItem)
            }
        }
        
        addItems(menuItems, to: nil)
        return snapshot
    }

}

// MARK: - UICollectionViewDelegate

extension OutlineViewController: UICollectionViewDelegate {

    private func splitViewWantsToShowDetail() -> Bool {
        return splitViewController?.traitCollection.horizontalSizeClass == .regular
    }
    
    private func pushOrPresentViewController(viewController: UIViewController) {
        if splitViewWantsToShowDetail() {
            let navVC = UINavigationController(rootViewController: viewController)
            splitViewController?.showDetailViewController(navVC, sender: navVC) // Replace the detail view controller.
            
            if navigationController!.traitCollection.userInterfaceIdiom == .mac {
                navVC.navigationBar.isHidden = true
            }
        } else {
            navigationController?.pushViewController(viewController, animated: true) // Just push instead of replace.
        }
    }
    
    private func pushOrPresentStoryboard(storyboardName: String) {
        let exampleStoryboard = UIStoryboard(name: storyboardName, bundle: .module)
        if let exampleViewController = exampleStoryboard.instantiateInitialViewController() {
            pushOrPresentViewController(viewController: exampleViewController)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let menuItem = self.dataSource.itemIdentifier(for: indexPath) else { return }
        
        collectionView.deselectItem(at: indexPath, animated: true)
    
        if let storyboardName = menuItem.storyboardName {
            pushOrPresentStoryboard(storyboardName: storyboardName)
            
            if navigationController!.traitCollection.userInterfaceIdiom == .mac {
                if let windowScene = view.window?.windowScene {
                    if #available(iOS 15, *) {
                        windowScene.subtitle = menuItem.title
                    }
                }
            }
        }
    }
    
}
