# Build an IPA with GitHub Actions

The `Build iOS IPA` workflow uses GitHub's standard Apple Silicon `macos-15`
runner with Xcode 26.3 already installed. You can start it from Linux or an iPad
browser. No Apple ID, signing certificate, or repository secret is required to
compile and package the app.

## Start the workflow

1. Commit and push the workflow and its build scripts to your fork's default
   branch (`main`). GitHub only exposes the manual run button after the
   `workflow_dispatch` workflow exists on that branch.
2. Open your fork's **Actions** tab. Enable workflows if GitHub asks.
3. Select **Build iOS IPA**, then **Run workflow**, choose `main`, and confirm.
4. After both jobs succeed, open the run and download **Madeira-IPA** under
   **Artifacts**. Extract the downloaded ZIP to obtain `Madeira.ipa`.

For this fork: <https://github.com/jppan/Madeira/actions>.

The equivalent command after pushing is:

```sh
gh workflow run build-ios.yml --repo jppan/Madeira --ref main
gh run list --repo jppan/Madeira --workflow build-ios.yml
# Use the run ID printed above:
gh run watch RUN_ID --repo jppan/Madeira
gh run download RUN_ID --repo jppan/Madeira --name Madeira-IPA --dir dist
```

## What the jobs do

The first job compiles LLVM 15.0.7's host table generator and iOS static
libraries. It caches the completed iOS libraries and headers using a key that
includes the Xcode build, runner architecture, and build recipe. Partial LLVM
builds are not cached. The second job restores those files, checks out recursive
submodules, prepares Wine's host tools and generated headers, and builds FEX,
FreeType, GnuTLS, wineserver, Wine's iOS libraries, and DXMT. It downloads the
official Microsoft Visual C++ runtime and extracts its x64 DLLs during the run.
The existing tracked Windows PE modules are reused; this is not a rebuild of
every binary in the repository.

The final step stages the bundled licenses, invokes `xcodebuild` in **Debug**,
and packages `Payload/Madeira.app`. Debug follows the repository's report of
guest crashes in Release. The effective minimum OS is **iOS 18**, matching the
DXMT and LLVM libraries. The IPA has an ad-hoc signature carrying the requested
entitlements, and must be re-signed by your sideloading tool before installation.
The signing profile and sideloading tool determine which entitlements are
actually granted. JIT still needs debugger attachment on the device.

## Timing, logs, and limitations

Allow several hours for the first run. Each job has GitHub's six-hour maximum;
separating LLVM gives the application build its own time budget. Subsequent
runs reuse LLVM, but rebuild the other native libraries. IPA artifacts expire
after three days, diagnostic artifacts after seven days. You can download them
to keep local copies.

The workflow has been syntax-checked on Linux; an end-to-end GitHub macOS build
has not yet been verified. It may expose additional clean-build problems in
the upstream project. A green build also does not establish that games run
correctly on an iPhone. If a job fails, open its failing step and download the
corresponding logs artifact. Fix the reported problem, push, and run again.
If you change Xcode, choose a version listed in the runner image documentation
and update `DEVELOPER_DIR` in the workflow.

Standard hosted runners are free for public repositories, subject to GitHub's
usage policies and separate cache/artifact storage limits. This workflow runs
only when manually started; commits and pull requests do not trigger it.

## Build-script provenance

The initial `scripts/build-ipa.sh`, `scripts/build/*.sh`, and
`build/wineserver/bootstrap.sh` were adapted from JMRBDev's upstream
[pull request #14](https://github.com/willfaust/Madeira/pull/14), commit
`ef496822ca427b4b000eaf7c78d3a570e23182e1`. That contribution reports a successful
local Apple Silicon build; it is not evidence that this workflow has passed.
This fork adds the Actions workflow, a compatible CMake version, Debug
packaging, license staging, download verification, and completed-build markers.
It also handles the current Microsoft installer's nested CAB layout and
architecture suffixes; all twelve extracted x64 DLLs were verified locally
against the original payloads, byte for byte.

References:

- [GitHub macOS runner specifications](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job)
- [macOS 15 Apple Silicon runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md)
- [Manually running a workflow](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)
- [Actions limits](https://docs.github.com/en/actions/reference/limits)
