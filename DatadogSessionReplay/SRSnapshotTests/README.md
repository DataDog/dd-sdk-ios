## SRSnapshotTests

The Snapshot Tests project is an additional layer of integration testing for the `DatadogSessionReplay` product. Instead of asserting JSON attributes in the code, it renders SR wireframes into PNGs and compares them against reference images using a perceptual precision algorithm.

### Launching `SRSnapshotTests.xcworkspace`

The `SRSnapshotTests.xcworkspace` depends on `dd-sdk-ios/Package.swift` but requires the `dd-sdk-ios/TestUtilities` library, which is not defined statically in the root package. To add it dynamically, we leverage the `DD_TEST_UTILITIES_ENABLED` ENV variable respected by the main package.

To open the project, use script from the `tools/` directory:
```
./tools/sr-snapshot-test.sh open-project
```

Otherwise, if launched directly tests will not compile due to `Missing package product 'TestUtilities'`.

### Managing Snapshot Files

PNG files are stored in a separate repository. To manage them, use `make` at the repository root.

To push new or updated local PNGs to the remote repo:
```
./tools/sr-snapshot-test.sh push
```

To pull PNGs from the remote repo:
```
./tools/sr-snapshot-test.sh pull
```

**Note**: Both commands require the [GitHub CLI](https://cli.github.com/) to be installed and authorized on the machine.
