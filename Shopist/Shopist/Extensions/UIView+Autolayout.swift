/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

extension UIView {
    func cover(_ superview: UIView) {
        superview.addSubview(self)
        self.translatesAutoresizingMaskIntoConstraints = false
        let container = superview.layoutMarginsGuide
        container.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        container.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
        container.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        container.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
    }

    func center(in superview: UIView) {
        superview.addSubview(self)
        self.translatesAutoresizingMaskIntoConstraints = false
        let container = superview.layoutMarginsGuide
        container.centerXAnchor.constraint(equalTo: self.centerXAnchor).isActive = true
        container.centerYAnchor.constraint(equalTo: self.centerYAnchor).isActive = true
        container.leadingAnchor.constraint(lessThanOrEqualTo: self.leadingAnchor).isActive = true
        container.trailingAnchor.constraint(greaterThanOrEqualTo: self.trailingAnchor).isActive = true
    }
}
