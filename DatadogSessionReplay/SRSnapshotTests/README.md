## SRSnapshotTests

The Snapshot Tests project is an additional layer of integration testing for the `DatadogSessionReplay` product. Instead of asserting JSON attributes in the code, it renders SR wireframes into PNGs and compares them against reference images using a perceptual precision algorithm.

### Launching `SRSnapshotTests.xcworkspace`

The `SRSnapshotTests.xcworkspace` depends on `dd-sdk-ios/Package.swift` but requires the `dd-sdk-ios/TestUtilities` library, which is not defined statically in the root package. To add it dynamically, we leverage the `DD_TEST_UTILITIES_ENABLED` ENV variable respected by the main package.

To open the project, use `make` at the repository root:
```
make sr-snapshot-tests-open
```

Otherwise, if launched directly tests will not compile due to `Missing package product 'TestUtilities'`.

### Managing Snapshot Files

PNG files are stored in a separate repository. To manage them, use `make` at the repository root.

To push new or updated view-tree PNGs to the remote repo:
```
make sr-snapshots-push
```

To pull view-tree PNGs from the remote repo:
```
make sr-snapshots-pull
```

To test view-tree snapshot comparison locally:
```
make sr-snapshot-test
```

### Layer tree snapshots

Use `SNAPSHOT_ENV` with the Make commands to select a simulator and its reference images.
Omit it to use the default shown below.

```sh
make sr-layer-snapshots-pull SNAPSHOT_ENV=ios-26.0.1-iphone17
make sr-layer-snapshot-test SNAPSHOT_ENV=ios-26.0.1-iphone17
make sr-layer-snapshots-push SNAPSHOT_ENV=ios-26.0.1-iphone17
```

[SnapshotEnvironments.json](SRLayerSnapshotTests/SnapshotEnvironments.json) defines the environments and the default.
Install the selected simulator before running tests.
Each environment has its own `_snapshots_/<environment>` folder, while PNG names, pointer hashes, and the image repository stay the same.

To update references, pull the existing images and set `shouldRecord = true` in `SRLayerSnapshotTests.swift`.
Run the tests to save new images and expect the image assertions to fail.
Restore `shouldRecord = false`, review the images, rerun the tests, and push the updated references.

In Xcode, select the `SRLayerSnapshotTests` scheme and a supported simulator.
The tests select the matching references automatically when `SNAPSHOT_ENV` is empty.
If no environment matches or more than one matches, the tests fail with an explanation.

**Note**: Pulling and pushing snapshots requires the [GitHub CLI](https://cli.github.com/) to be installed and authorized on the machine.
