# SPMProject

`SPMProject` is a skeleton of an SPM package used for testing SPM compatibility of the current branch.

After pushing current branch to remote, run:
```bash
$ make
```
to check if SPM is able to fetch `Datadog` dependency from current branch and build the project.

## Important Note:

`make` auto-magically changes current branch for `Datadog` dependency. 
By default, current branch is `master`; if you open `SPMProject.xcodeproj` and build, you will fetch `Datadog:master`
