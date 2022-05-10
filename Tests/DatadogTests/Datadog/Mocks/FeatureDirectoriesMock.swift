/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog

/// `FeatureDirectories` pointing to subfolders in `/var/folders/`.
/// Those subfolders do not exist by default and should be created and deleted by calling `.create()` and `.delete()` in each test,
/// which guarantees clear state before and after test.
let temporaryFeatureDirectories = FeatureDirectories(
    deprecated: [],
    unauthorized: obtainUniqueTemporaryDirectory(),
    authorized: obtainUniqueTemporaryDirectory()
)

extension FeatureDirectories {
    /// Creates temporary folder for each directory.
    func create() {
        authorized.create()
        unauthorized.create()
    }

    /// Deletes each temporary folder.
    func delete() {
        authorized.delete()
        unauthorized.delete()
    }
}
