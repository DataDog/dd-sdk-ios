/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

@testable import Datadog

/// `CoreDirectory` pointing to subfolders in `/var/folders/`.
/// This location does not exist by default and should be created and deleted by calling `.create()` and `.delete()` in each test,
/// which guarantees clear state before and after test.
let temporaryCoreDirectory = CoreDirectory(
    osDirectory: obtainUniqueTemporaryDirectory(),
    coreDirectory: obtainUniqueTemporaryDirectory()
)

extension CoreDirectory {
    /// Creates temporary core directory.
    @discardableResult
    func create() -> Self {
        osDirectory.create()
        coreDirectory.create()
        return self
    }

    /// Deletes temporary core directory.
    func delete() {
        osDirectory.delete()
        coreDirectory.delete()
    }
}

/// `FeatureDirectories` pointing to subfolders in `/var/folders/`.
/// Those subfolders do not exist by default and should be created and deleted by calling `.create()` and `.delete()` in each test,
/// which guarantees clear state before and after test.
let temporaryFeatureDirectories = FeatureDirectories(
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
