/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal class BenchmarkViewController: UIViewController {
    override func viewWillAppear(_ animated: Bool) {
        benchmark.beforeStart()
    }

    override func viewDidAppear(_ animated: Bool) {
        benchmark.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        benchmark.stop()
    }

    override func viewDidDisappear(_ animated: Bool) {
        benchmark.afterStop()
    }
}
