/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

extension UIButton {
    func disableFor(seconds: TimeInterval) {
        let originalBackgroundColor = self.backgroundColor

        self.isEnabled = false
        if #available(iOS 13.0, *) {
            self.backgroundColor = .systemGray4
        } else {
            self.backgroundColor = .systemGray
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.isEnabled = true
            self?.backgroundColor = originalBackgroundColor
        }
    }
}
