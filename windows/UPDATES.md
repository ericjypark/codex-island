# Windows installers and updates

CodexIsland uses Velopack 1.2.0 for Windows installation and updates. The Windows 11
app has separate x64 and ARM64 installers. Each includes the .NET desktop
runtime and creates a Start menu entry. Installing does not require a .NET SDK.

The current installers are unsigned. Windows can show an unknown publisher
warning. Download only from the project's GitHub releases. The updater verifies
downloaded packages against the SHA-256 checksum in the release feed; this does
not replace an Authenticode publisher signature.

## App behavior

- **Settings > General > Updates > Check** checks immediately, even when automatic
  checks are disabled. The tray menu also opens the update controls.
- Automatic checks run once a day, beginning shortly after launch when due. Failed
  checks retry after an hour. Disabling the toggle stops scheduled requests.
- A newly available version produces one tray notification. Downloading requires
  a click, and installing requires **Restart and update**.
- An ordinary app relaunch leaves a downloaded update pending. The updater does
  not silently apply it on startup.
- Downloads report progress. Connection or verification failures retain the
  installed application. A failed download can be retried.
- Local settings, history, and caches remain under
  `%LOCALAPPDATA%\CodexIslandPrototype`, outside the replaceable installation
  directory `%LOCALAPPDATA%\CodexIsland\current`. Custom `--data-dir` profiles
  and the chosen live/demo mode survive an update restart.
- Launch at Login uses the stable launcher outside `current`, with the selected
  data profile. Standalone development copies cannot receive installer updates.

## Build

From Windows PowerShell with the .NET 10 SDK installed:

```powershell
./windows/build-installer.ps1 -Runtime win-x64 -Unsigned
./windows/build-installer.ps1 -Runtime win-arm64 -Unsigned
```

The script reads the repository's `VERSION`, pins the packaging tool and app
library to the same version, and writes to `windows/artifacts/installers/`.
The installers are named `CodexIsland-win-x64-preview-Setup.exe` and
`CodexIsland-win-arm64-preview-Setup.exe`. Output also contains the full update
package, architecture-specific feed, and a download manifest with its checksum.
Reusing an output directory with an older full package allows Velopack to create
a delta update.

After configuring Azure Artifact Signing, pass `-AzureTrustedSignFile` with the
local signing metadata file instead of `-Unsigned`. The build verifies the final
installer's Authenticode signature. Keep existing preview channels available
when introducing signed builds so preview installations continue receiving
updates. A future stable channel is an explicit distribution choice.

## Release integration

The Windows workflow builds both architectures and runs the logic checks. Normal
branch and pull-request builds retain downloadable CI artifacts without publishing
a release. A version tag must match `VERSION`.

On a version tag, the Windows publisher waits for the existing non-draft,
non-prerelease macOS release to
contain its DMG and appcast, then attaches only Windows files. It does not create
or edit the release, change its latest status, modify Sparkle, or synchronize the
Homebrew cask. Existing assets with different contents are never overwritten.
Availability manifests are uploaded after the installer and feed files.

The landing page detects these manifests and exposes x64 and ARM64 downloads only
after their assets exist. Drafts and prereleases are excluded. Mac-only releases
do not hide the newest available Windows installer. Before any Windows release is published, the installed app
reports that the Windows feed is not published yet.

## Validation

`tests/logic/AppUpdateTests.cs` covers scheduling, disabled automatic checks,
manual checks, duplicate requests, errors, cancellation, pending downloads, and
explicit restart behavior. These checks run in the existing Windows logic suite.

`tests/check-installer-upgrade.ps1` exercises the real Settings controls in separate
`CodexIsland.UpdateTest.*` installations. Test packages embed a local feed with
`-PackageId` and `-TestFeed`; the build rejects a local feed in a public package.
The test installs version 0.0.1, upgrades to 0.0.2, verifies a normal relaunch does
not install early, and compares the complete preferences and SQLite history files
before and after. `-CorruptFirst` verifies rejection of a modified full package.

Both ARM64 and x64 installer upgrade paths were exercised on Windows 11 ARM in
Parallels. x64 ran under Windows emulation; this is not native x64 hardware or
performance validation. Code signing and hosted release publication require their
own verification when configured and released.
