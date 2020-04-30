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
        self.backgroundColor = .systemGray4

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.isEnabled = true
            self?.backgroundColor = originalBackgroundColor
        }
    }
}
