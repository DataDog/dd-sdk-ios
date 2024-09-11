/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that demonstrates how to customize a `UISearchBar`.
*/

import UIKit

class CustomSearchBarViewController: UIViewController {
    // MARK: - Properties

    @IBOutlet weak var searchBar: UISearchBar!

    // MARK: - View Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()

        configureSearchBar()
    }

    // MARK: - Configuration
    
    func configureSearchBar() {
        searchBar.showsCancelButton = true
        searchBar.showsBookmarkButton = true

        searchBar.tintColor = UIColor.systemPurple

        searchBar.backgroundImage = UIImage(named: "search_bar_background", in: .module, compatibleWith: nil)

        // Set the bookmark image for both normal and highlighted states.
        let bookImage = UIImage(systemName: "bookmark")
        searchBar.setImage(bookImage, for: .bookmark, state: .normal)

        let bookFillImage = UIImage(systemName: "bookmark.fill")
        searchBar.setImage(bookFillImage, for: .bookmark, state: .highlighted)
    }
}

// MARK: - UISearchBarDelegate

extension CustomSearchBarViewController: UISearchBarDelegate {
	func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        Swift.debugPrint("The custom search bar keyboard \"Search\" button was tapped.")
		
		searchBar.resignFirstResponder()
	}
	
	func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        Swift.debugPrint("The custom search bar \"Cancel\" button was tapped.")
		
		searchBar.resignFirstResponder()
	}
	
	func searchBarBookmarkButtonClicked(_ searchBar: UISearchBar) {
        Swift.debugPrint("The custom \"bookmark button\" inside the search bar was tapped.")
	}
	
}
