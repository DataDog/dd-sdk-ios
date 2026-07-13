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

Layer-tree snapshots use a separate folder, scheme, and simulator. To push new or updated layer-tree PNGs to the remote repo:
```
make sr-layer-snapshots-push
```

To pull layer-tree PNGs from the remote repo:
```
make sr-layer-snapshots-pull
```

To test layer-tree snapshot comparison locally:
```
make sr-layer-snapshot-test
```

**Note**: Pulling and pushing snapshots requires the [GitHub CLI](https://cli.github.com/) to be installed and authorized on the machine.
