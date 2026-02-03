# Integration Tests

This project contains the UI integration tests for the iOS SDK.


## Setup

Before opening the project, ensure Xcode is closed. Then, set up the correct environment by running the following command:

```bash
make ui-test-podinstall
``` 

## Troubleshooting Dependency Graph Errors

If you encounter dependency graph errors, follow these steps:

1. Update your branch
Rebase your branch with the latest `develop` to ensure you have all recent changes.

2. Clean the project
Run the following command to remove cached builds and other temporary files:
```bash
make clean
```

3. Update CocoaPods dependencies
Navigate into the IntegrationTests directory, update the pods, and then return to the project root:
```bash
cd IntegrationTests
pod update
cd ..
```

4. Reinstall the UI Test dependencies
Finally, re-run:
```bash
make ui-test-podinstall
```
