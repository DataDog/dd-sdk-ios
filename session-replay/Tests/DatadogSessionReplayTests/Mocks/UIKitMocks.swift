/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

extension UIColor: AnyMockable, RandomMockable {
    static func mockAny() -> Self {
        return UIColor.green as! Self
    }

    static func mockRandom() -> Self {
        return mockRandomWith(alpha: .mockRandom(min: 0, max: 1))
    }

    static func mockRandomWith(alpha: CGFloat) -> Self {
        return UIColor(
            red: .mockRandom(min: 0, max: 1),
            green: .mockRandom(min: 0, max: 1),
            blue: .mockRandom(min: 0, max: 1),
            alpha: alpha
        ) as! Self
    }
}

extension UIView: AnyMockable, RandomMockable {
    static func mockAny() -> Self {
        return UIView(frame: .init(x: 0, y: 0, width: 200, height: 400)) as! Self
    }

    static func mockRandom() -> Self {
        let view = UIView(frame: .mockRandom())
        view.backgroundColor = .mockRandom()
        view.layer.borderColor = .mockRandom()
        view.layer.backgroundColor = .mockRandom()
        view.layer.cornerRadius = .mockRandom(min: 0, max: 5)
        view.alpha = .mockRandom(min: 0, max: 1)
        view.isHidden = .random()
        return view as! Self
    }
}
