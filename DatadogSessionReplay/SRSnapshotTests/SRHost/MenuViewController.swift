/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal class MenuViewController: UITableViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Fixture.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell()

        if #available(iOS 14.0, *) {
            var content = cell.defaultContentConfiguration()
            content.text = Fixture.allCases[indexPath.item].menuItemTitle
            cell.contentConfiguration = content
        } else {
            let label = UILabel(frame: .init(x: 10, y: 0, width: tableView.bounds.width, height: 44))
            label.text = Fixture.allCases[indexPath.item].menuItemTitle
            cell.addSubview(label)
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        show(Fixture.allCases[indexPath.item].instantiateViewController(), sender: self)
    }
}
