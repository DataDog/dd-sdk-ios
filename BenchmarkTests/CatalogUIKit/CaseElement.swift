/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Test case element that serves our UITableViewCells.
*/

import UIKit

struct CaseElement {
    var title: String // Visual title of the cell (table section header title)
    var cellID: String // Table view cell's identifier for searching for the cell within the nib file.
    
    typealias ConfigurationClosure = (UIView) -> Void
    var configHandler: ConfigurationClosure // Configuration handler for setting up the cell's subview.
    
    init<V: UIView>(title: String, cellID: String, configHandler: @escaping (V) -> Void) {
        self.title = title
        self.cellID = cellID
        self.configHandler = { view in
            guard let view = view as? V else { fatalError("Impossible") }
            configHandler(view)
        }
    }
    
    func targetView(_ cell: UITableViewCell?) -> UIView? {
        return cell != nil ? cell!.contentView.subviews[0] : nil
    }
}
