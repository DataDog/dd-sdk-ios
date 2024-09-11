/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that demonstrates how to use SF Symbols.
*/

import UIKit

class SymbolViewController: BaseTableViewController {
    
    // Cell identifier for each SF Symbol table view cell.
    enum SymbolKind: String, CaseIterable {
        case plainSymbol
        case tintedSymbol
        case largeSizeSymbol
        case hierarchicalColorSymbol
        case paletteColorsSymbol
        case preferringMultiColorSymbol
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        testCells.append(contentsOf: [
            CaseElement(title: NSLocalizedString("PlainSymbolTitle", bundle: .module, comment: ""),
                        cellID: SymbolKind.plainSymbol.rawValue,
                        configHandler: configurePlainSymbol),
            CaseElement(title: NSLocalizedString("TintedSymbolTitle", bundle: .module, comment: ""),
                        cellID: SymbolKind.tintedSymbol.rawValue,
                        configHandler: configureTintedSymbol),
            CaseElement(title: NSLocalizedString("LargeSymbolTitle", bundle: .module, comment: ""),
                        cellID: SymbolKind.largeSizeSymbol.rawValue,
                        configHandler: configureLargeSizeSymbol)
        ])
        
        if #available(iOS 15, *) {
            // These type SF Sybols, and variants are available on iOS 15, Mac Catalyst 15 or later.
            testCells.append(contentsOf: [
                CaseElement(title: NSLocalizedString("HierarchicalSymbolTitle", bundle: .module, comment: ""),
                            cellID: SymbolKind.hierarchicalColorSymbol.rawValue,
                            configHandler: configureHierarchicalSymbol),
                CaseElement(title: NSLocalizedString("PaletteSymbolTitle", bundle: .module, comment: ""),
                            cellID: SymbolKind.paletteColorsSymbol.rawValue,
                            configHandler: configurePaletteColorsSymbol),
                CaseElement(title: NSLocalizedString("PreferringMultiColorSymbolTitle", bundle: .module, comment: ""),
                            cellID: SymbolKind.preferringMultiColorSymbol.rawValue,
                            configHandler: configurePreferringMultiColorSymbol)
            ])
        }
    }

    // MARK: - UITableViewDataSource

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let cellTest = testCells[indexPath.section]
        let cell = tableView.dequeueReusableCell(withIdentifier: cellTest.cellID)
        return cell!.contentView.bounds.size.height
    }
    
    // MARK: - Configuration
    
    func configurePlainSymbol(_ imageView: UIImageView) {
        let image = UIImage(systemName: "cloud.sun.rain.fill")
        imageView.image = image
    }
    
    func configureTintedSymbol(_ imageView: UIImageView) {
        let image = UIImage(systemName: "cloud.sun.rain.fill")
        imageView.image = image
        imageView.tintColor = .systemPurple
    }
    
    func configureLargeSizeSymbol(_ imageView: UIImageView) {
        let image = UIImage(systemName: "cloud.sun.rain.fill")
        imageView.image = image
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 32, weight: .heavy, scale: .large)
        imageView.preferredSymbolConfiguration = symbolConfig
    }
    
    @available(iOS 15.0, *)
    func configureHierarchicalSymbol(_ imageView: UIImageView) {
        let imageConfig = UIImage.SymbolConfiguration(hierarchicalColor: UIColor.systemRed)
        let hierarchicalSymbol = UIImage(systemName: "cloud.sun.rain.fill")
        imageView.image = hierarchicalSymbol
        imageView.preferredSymbolConfiguration = imageConfig
    }
    
    @available(iOS 15.0, *)
    func configurePaletteColorsSymbol(_ imageView: UIImageView) {
        let palleteSymbolConfig = UIImage.SymbolConfiguration(paletteColors: [UIColor.systemRed, UIColor.systemOrange, UIColor.systemYellow])
        let palleteSymbol = UIImage(systemName: "battery.100.bolt")
        imageView.image = palleteSymbol
        imageView.backgroundColor = UIColor.darkText
        imageView.preferredSymbolConfiguration = palleteSymbolConfig
    }
    
    @available(iOS 15.0, *)
    func configurePreferringMultiColorSymbol(_ imageView: UIImageView) {
        let preferredSymbolConfig = UIImage.SymbolConfiguration.preferringMulticolor()
        let preferredSymbol = UIImage(systemName: "circle.hexagongrid.fill")
        imageView.image = preferredSymbol
        imageView.preferredSymbolConfiguration = preferredSymbolConfig
    }
    
}
