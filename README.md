# LotCom WIP Printer

[![CI/CD](https://github.com/Yamada-North-America/LotCom-printer/actions/workflows/cicd.yml/badge.svg?branch=stable)](https://github.com/Yamada-North-America/LotCom-printer/actions/workflows/cicd.yml) [![CodeQL](https://github.com/Yamada-North-America/LotCom-printer/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/Yamada-North-America/LotCom-printer/actions/workflows/github-code-scanning/codeql)

[LotCom](https://github.com/LotCom) System dedicated Work-in-Progress part Label Printing application.

Low-level, high-security printing software used to produce lot-tracing labels. Provides a simple interface allowing the entry of Production Data and printing of Labels that pass that data through the Production flow. 

### This is a privately-directed project

Please read the [Contribution Guide](https://github.com/Yamada-North-America/LotCom-printer/blob/main/CONTRIBUTING.md) for more information.

## Build a stable release

The **Build release** workflow supports manual runs and version tags, following LotCom-watcher's release
process. It creates a **draft GitHub Release** containing `LotComPrinter_VERSION.msi`,
`LotComPrinter_VERSION_win-x64.zip`, and `SHA256SUMS.txt`. Packages are also kept as Actions artifacts for
30 days. The unpackaged Windows x64 payload includes both .NET and the Windows App SDK runtime.

Merge this implementation into **stable**, then make **stable the default branch**. GitHub requires
`workflow_dispatch` on the default branch before it displays **Run workflow**. No companion change to
`develop` is needed when stable is the default.

### Manual release

1. Open **Actions → Build release → Run workflow**.
2. Enter a new three-part version without `v`, for example `1.0.5`.
3. Run the workflow, then review and publish the draft under **Releases**.

Manual runs always check out `stable`, regardless of the branch selected in the dispatch menu. The
version is applied to the compiled assembly and MSI during the build. MAUI receives a four-part Windows
display version (`1.0.5.0` for release `1.0.5`), as required by the existing Windows project.

### Tag release

Create a tag on a commit that belongs to stable and includes this workflow:

```sh
git switch stable
git pull --ff-only
git tag v1.0.5
git push origin v1.0.5
```

Annotated tags work too. Unprefixed three-part tags such as `1.0.5` are also accepted. Tags on commits
outside stable are rejected. Normal branch pushes do not create stable releases. The existing
`buildalpha.yml` remains the separate develop/alpha workflow.

Use three numeric components without leading zeroes or prerelease suffixes. MSI limits major/minor to
255 and patch to 65535. **Use a new three-part version family:** historical tags such as `1.0.4.0` are
protected, so choose `1.0.5` rather than reusing `1.0.4`. Windows Installer compares only the first three
version components for upgrades; new four-part release inputs/tags are therefore rejected. Existing
releases under either `VERSION` or `vVERSION` and conflicting tags are rejected as well.

A manual run creates `vVERSION` at the exact built stable commit. The built-in `GITHUB_TOKEN` does not
start a second workflow for this tag. If a run fails before creating a draft, fix the problem and rerun
it. If asset upload fails after draft creation, delete the incomplete draft, keep its tag, and rerun
the same commit (or choose a new version). Existing release assets are never overwritten.

## Build requirements

The workflow was compared with the original stable action and retains Printer's specific requirements:

- Windows 2022 with Visual Studio/MSBuild and the Windows SDK, and the .NET 9 SDK selected through
  `global.json`, even when a newer SDK is installed. The application targets
  `net9.0-windows10.0.19041.0`, MAUI Controls 9.0.90, and unpackaged Windows desktop output.
- The **maui-windows** workload installed before restoring/publishing. Android, iOS, and Mac Catalyst
  targets are commented out in the current project, so Android/mobile workloads are not needed for
  this Windows release. This differs from Watcher's non-MAUI Worker project.
- The original `RuntimeIdentifierOverride=win10-x64`, `WindowsPackageType=None`,
  `WindowsAppSDKSelfContained=true`, and .NET self-contained settings. `dotnet publish` restores with
  the same properties used for publishing and packages the resulting files recursively. The script
  checks for the executable, .NET native runtime, and WinUI native runtime before building the MSI.
- `LotCom-libraries` checked out as a sibling of `LotCom-printer`, matching the project reference, at
  pinned revision `ef2da369b7bda48abc0d3b073625754dcae10bd8` (the inspected develop revision and the same pin
  used by Watcher). Its revision is included in release notes.
- WixSharp 2.7.1 and .NET Framework 4.7.2 reference assemblies for the setup project. The Windows runner
  supplies the .NET Framework runtime. WiX 4.0.6, its **UI and Util extensions**, and the .NET 8 runtime
  are installed explicitly, avoiding the original action's accidental upgrade to WiX 7.

The NuGet cache path uses the repository's actual `LotCoMPrinter/packages.lock.json` casing. Public
library checkout and the repository token replace `PAT_1`. Only the release job receives `contents: write`;
repository policy must permit that permission.

## Installer

`installer/Program.cs` adapts `LotCom-printer-setup` commit `8b2ad9bb0894e2a914b411d6e01610bbfae8fe07`.
It accepts explicit publish/output paths, removing hard-coded runner drives and build-directory paths.
Keeping setup source with the application also makes tag builds use the corresponding installer code.
It retains the original product-code algorithm, upgrade code, YNA metadata, application-close prompt,
and Start menu/Desktop shortcuts. It installs under `%ProgramData%\Yamada North America\LotCom Printer`
with administrator privileges. The Control Panel icon comes from the compiled executable instead of
a hard-coded generated PNG path. The installer uses a progress-only UI without a custom license file.
Packages are unsigned.

**Existing installer identity issue:** the original Printer and Watcher setups both use upgrade GUID
`B8922687-A74A-45D4-96AA-17C91224DB7A`. This change preserves it for compatibility with deployed Printer
installations. Windows Installer can consequently treat Watcher as a related product, blocking an
installation or removing it during an upgrade. Review/test installation on machines that have both
applications before publishing/deploying a release; separating those identities needs an explicit
migration plan.

For local packaging, use PowerShell 7 on Windows, install the SDK/runtimes above, and clone
`LotCom-libraries` alongside this repository at the pinned revision. Then run:

```powershell
dotnet workload install maui-windows
dotnet tool install --global wix --version 4.0.6 --allow-roll-forward
wix extension add --global WixToolset.UI.wixext/4.0.6
wix extension add --global WixToolset.Util.wixext/4.0.6
./.github/scripts/build-release.ps1 -Version 1.0.5
```

Packages are written to `artifacts/packages/`.
