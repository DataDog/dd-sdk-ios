# SPMProject

`SPMProject` is a skeleton project for testing SPM compatibility of the current branch.

After pushing current branch to remote, run:
```bash
$ make
```
This creates the `SPMProject.xcodeproj` from `SPMProject.xcodeproj.src` by replacing the `REMOTE_GIT_BRANCH` string with the name of the remote branch.

Launch the `SPMProject.xcodeproj` to check if SPM is able to fetch the `Datadog` package from remote and build the project.

To update the setup in `SPMProject.xcodeproj`, use:
```bash
make create-src-from-xcodeproj
```
to apply the change back to the `SPMProject.xcodeproj.src`, so it can be committed to git.
