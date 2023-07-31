/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

extension UIButton {
    func disableFor(seconds: TimeInterval) {
        let completion = disableUntilCompletion()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            completion()
        }
    }

    func disableUntilCompletion() -> () -> Void {
        let originalBackgroundColor = self.backgroundColor

        self.isEnabled = false
        self.backgroundColor = .systemGray

        return {
            self.isEnabled = true
            self.backgroundColor = originalBackgroundColor
        }
    }
}
