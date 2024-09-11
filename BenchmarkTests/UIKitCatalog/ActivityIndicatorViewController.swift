/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that demonstrates how to use `UIActivityIndicatorView`.
*/

import UIKit

class ActivityIndicatorViewController: BaseTableViewController {
    
    // Cell identifier for each activity indicator table view cell.
    enum ActivityIndicatorKind: String, CaseIterable {
        case mediumIndicator
        case largeIndicator
        case mediumTintedIndicator
        case largeTintedIndicator
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        testCells.append(contentsOf: [
            CaseElement(title: NSLocalizedString("MediumIndicatorTitle", bundle: .module, comment: ""),
                        cellID: ActivityIndicatorKind.mediumIndicator.rawValue,
                        configHandler: configureMediumActivityIndicatorView),
            CaseElement(title: NSLocalizedString("LargeIndicatorTitle", bundle: .module, comment: ""),
                        cellID: ActivityIndicatorKind.largeIndicator.rawValue,
                        configHandler: configureLargeActivityIndicatorView)
        ])
        
        if traitCollection.userInterfaceIdiom != .mac {
            // Tinted activity indicators available only on iOS.
            testCells.append(contentsOf: [
                CaseElement(title: NSLocalizedString("MediumTintedIndicatorTitle", bundle: .module, comment: ""),
                            cellID: ActivityIndicatorKind.mediumTintedIndicator.rawValue,
                            configHandler: configureMediumTintedActivityIndicatorView),
                CaseElement(title: NSLocalizedString("LargeTintedIndicatorTitle", bundle: .module, comment: ""),
                            cellID: ActivityIndicatorKind.largeTintedIndicator.rawValue,
                            configHandler: configureLargeTintedActivityIndicatorView)
            ])
        }
    }
    
    // MARK: - Configuration
    
    func configureMediumActivityIndicatorView(_ activityIndicator: UIActivityIndicatorView) {
        activityIndicator.style = UIActivityIndicatorView.Style.medium
        activityIndicator.hidesWhenStopped = true
        
        activityIndicator.startAnimating()
        // When the activity is done, be sure to use UIActivityIndicatorView.stopAnimating().
    }
    
    func configureLargeActivityIndicatorView(_ activityIndicator: UIActivityIndicatorView) {
        activityIndicator.style = UIActivityIndicatorView.Style.large
        activityIndicator.hidesWhenStopped = true

        activityIndicator.startAnimating()
        // When the activity is done, be sure to use UIActivityIndicatorView.stopAnimating().
    }
    
    func configureMediumTintedActivityIndicatorView(_ activityIndicator: UIActivityIndicatorView) {
        activityIndicator.style = UIActivityIndicatorView.Style.medium
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = UIColor.systemPurple

        activityIndicator.startAnimating()
        // When the activity is done, be sure to use UIActivityIndicatorView.stopAnimating().
    }
    
    func configureLargeTintedActivityIndicatorView(_ activityIndicator: UIActivityIndicatorView) {
        activityIndicator.style = UIActivityIndicatorView.Style.large
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = UIColor.systemPurple

        activityIndicator.startAnimating()
        // When the activity is done, be sure to use UIActivityIndicatorView.stopAnimating().
    }
    
}
