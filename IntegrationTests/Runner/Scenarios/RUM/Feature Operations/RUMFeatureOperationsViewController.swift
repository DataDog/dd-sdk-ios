/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogRUM

enum Operation: String {
    case login = "login_flow"
    case photoUpload = "photo_upload"

    func callAsFunction() -> String { self.rawValue }

    enum Key: String {
        case photo1
        case photo2
        case photo3

        func callAsFunction() -> String { self.rawValue }
    }
}

final class RUMFeatureOperationsViewController: UIViewController {
    private static let viewName = "FeatureOperationsView"

    // MARK: - Login Flow Operations

    @IBAction func didTapStartLoginFlowButton(_ sender: Any) {
        rumMonitor.startFeatureOperation(
            name: Operation.login()
        )
    }

    @IBAction func didTapSucceedLoginFlowButton(_ sender: Any) {
        rumMonitor.succeedFeatureOperation(
            name: Operation.login(),
            attributes: [
                "user_type": "new_user"
            ]
        )
    }

    @IBAction func didTapFailLoginFlowButton(_ sender: Any) {
        rumMonitor.failFeatureOperation(
            name: Operation.login(),
            reason: .error,
            attributes: [
                "error_code": "invalid_credentials"
            ]
        )
    }

    // MARK: - Photo Upload Operations (with parallel instances)

    @IBAction func didTapStartParallelOperationsButton(_ sender: Any) {
        // Start multiple photo upload operations with different keys
        rumMonitor.startFeatureOperation(
            name: Operation.photoUpload(),
            operationKey: Operation.Key.photo1(),
            attributes: ["photo_id": "IMG_001", "size": "2.5MB"]
        )

        rumMonitor.startFeatureOperation(
            name: Operation.photoUpload(),
            operationKey: Operation.Key.photo2(),
            attributes: ["photo_id": "IMG_002", "size": "1.8MB"]
        )

        rumMonitor.startFeatureOperation(
            name: Operation.photoUpload(),
            operationKey: Operation.Key.photo3(),
            attributes: ["photo_id": "IMG_003", "size": "3.2MB"]
        )
    }

    @IBAction func didTapSucceedParallelOperationsButton(_ sender: Any) {
        // Succeed all photo upload operations
        rumMonitor.succeedFeatureOperation(
            name: Operation.photoUpload(),
            operationKey: Operation.Key.photo1()
        )

        rumMonitor.succeedFeatureOperation(
            name: Operation.photoUpload(),
            operationKey: Operation.Key.photo2()
        )

        rumMonitor.succeedFeatureOperation(
            name: Operation.photoUpload(),
            operationKey: Operation.Key.photo3()
        )
    }

    @IBAction func didTapFailParallelOperationsButton(_ sender: Any) {
        // Fail all photo upload operations
        rumMonitor.failFeatureOperation(
            name: Operation.photoUpload(),
            operationKey: Operation.Key.photo1(),
            reason: .error
        )

        rumMonitor.failFeatureOperation(
            name: Operation.photoUpload(),
            operationKey: Operation.Key.photo2(),
            reason: .abandoned
        )

        rumMonitor.failFeatureOperation(
            name: Operation.photoUpload(),
            operationKey: Operation.Key.photo3(),
            reason: .other
        )
    }
}
