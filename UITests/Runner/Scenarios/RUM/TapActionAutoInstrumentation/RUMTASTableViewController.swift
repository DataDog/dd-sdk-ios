/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal class RUMTASTableViewCustomCell: UITableViewCell {
    @IBOutlet weak var label: UILabel!
}

internal class RUMTASTableViewController: UITableViewController {
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 30
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell: UITableViewCell!

        if indexPath.item % 2 == 0 {
            let systemBasicCell = tableView.dequeueReusableCell(withIdentifier: "SystemBasicCell")!
            systemBasicCell.textLabel?.text = "Item \(indexPath.item)"
            cell = systemBasicCell
        } else {
            let customCell = tableView.dequeueReusableCell(withIdentifier: "CustomCell") as! RUMTASTableViewCustomCell
            customCell.label.text = "Item \(indexPath.item)"
            cell = customCell
        }

        cell.accessibilityIdentifier = "Item \(indexPath.item)"

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        navigationController?.popViewController(animated: true)
    }
}
