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
        superview.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        superview.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
        superview.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        superview.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
    }

    func center(in superview: UIView) {
        superview.addSubview(self)
        self.translatesAutoresizingMaskIntoConstraints = false
        superview.centerXAnchor.constraint(equalTo: self.centerXAnchor).isActive = true
        superview.centerYAnchor.constraint(equalTo: self.centerYAnchor).isActive = true
        superview.leadingAnchor.constraint(lessThanOrEqualTo: self.leadingAnchor).isActive = true
        superview.trailingAnchor.constraint(greaterThanOrEqualTo: self.trailingAnchor).isActive = true
    }
}
