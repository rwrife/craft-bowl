# Block Bowl Microsoft Store assets

All images are opaque RGB PNGs. The wallpaper is promotional artwork, not a gameplay
screenshot. The five screenshots are unaltered viewport captures of the Godot game
running on Windows, with no developer overlay.

| File | Dimensions / purpose |
| --- | --- |
| `wallpaper-1920x1080.png` | 1920 x 1080 branded desktop wallpaper / promotional artwork |
| `icons/Square300x300Logo.png` | 300 x 300 square icon |
| `icons/Square150x150Logo.png` | 150 x 150 square icon |
| `icons/Square71x71Logo.png` | 71 x 71 square icon |
| `short-description.txt` | Plain-text short listing description |
| `description.txt` | Plain-text full listing description |

Upload the 1920 x 1080 screenshots in filename order:

1. `screenshots/01-gameplay.png` - Live gameplay
2. `screenshots/02-play-selection.png` - Illustrated play selection
3. `screenshots/03-teams.png` - Team selection
4. `screenshots/04-roster.png` - Team roster and ratings
5. `screenshots/05-title.png` - Title screen

Use the wallpaper for promotional artwork only, not in the screenshot slots.
The release packaging script generates the separate 44 x 44, 150 x 150, and
50 x 50 manifest logos from the existing square icon and indexes them with MakePri.

## Build a Microsoft Store release

The **Release Windows Store** GitHub Actions workflow builds the portable Godot
game, not the Swift/iOS app. It runs on `windows-2022` with Godot 4.4.1 and its
matching x64 release template, verifies the download checksums, runs both gameplay
tests, and smoke-tests the exported executable before packaging with the Windows SDK.
It installs rcedit 2.0.0 for the executable's icon and version metadata. The raw
`App\BlockBowlLogo.obj` is shipped beside the PCK because the title screen reads its
vertex colors directly, whereas Godot's normal OBJ export only ships an imported mesh.
Exported Windows builds resolve that file relative to the executable, not the
launcher's working directory.

First reserve **Block Bowl** in Partner Center. Under **Product management > Product
identity**, copy the exact, case-sensitive values into repository **Settings >
Secrets and variables > Actions > Variables**:

| Repository variable | Partner Center value |
| --- | --- |
| `WINDOWS_STORE_IDENTITY_NAME` | Package/Identity/Name |
| `WINDOWS_STORE_PUBLISHER` | Package/Identity/Publisher (the full `CN=...` value) |
| `WINDOWS_STORE_PUBLISHER_DISPLAY_NAME` | Package/Properties/PublisherDisplayName |

The manifest display name is `Block Bowl` and must match the reserved product.
No signing certificate or Store API secrets are needed for this build-only workflow.

In **Actions > Release Windows Store > Run workflow**, select the release branch
and supply a package version such as `1.0.0.0`. Each component must be at most
65535, the first must be at least 1, and the fourth must stay `0` because the Store
reserves it. Increase the version for subsequent updates; reruns do not automatically
increment it. The workflow applies the selected version to both the MSIX identity
and the executable's file/product metadata.

Download the `windows-store-<version>-x64-<run-id>` artifact. It contains
`BlockBowl_<version>_x64.msix` and `release-evidence.json` with the source commit
and package SHA256. Upload the **MSIX**, not the artifact ZIP, to your Partner Center
submission's **Packages** page. The artifact is retained for 30 days.

The package targets Windows 10 1809 or later on x64 and declares `runFullTrust`
for the desktop game. Explain that capability if Partner Center requests it.
Run the Windows App Certification Kit and test on real hardware before submitting;
the workflow's smoke test does not replace certification or graphical testing.
This workflow does not upload to Partner Center, publish a GitHub Release, or
automatically publish the app to the Store.

The output is **unsigned for Store submission**: Microsoft Store signs the package
after certification. It is not a sideload installer; distribution outside the Store
requires separate certificate signing and trust setup. See Microsoft's
[package requirements](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/app-package-requirements).

### Local packaging

With Godot 4.4.1, the matching Windows x64 export template, rcedit configured in
**Editor Settings > Export > Windows**, and a Windows 10/11 SDK installed, run
from the repository root:

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://godot/tests/test_simulation.gd
godot --headless --path . --script res://godot/tests/test_app_replay.gd
New-Item -ItemType Directory -Force -Path .\build\windows
godot --headless --path . --export-release "Windows Store" ".\build\windows\BlockBowl.exe"
New-Item -ItemType Directory -Force -Path .\build\windows\App
Copy-Item .\App\BlockBowlLogo.obj .\build\windows\App\BlockBowlLogo.obj
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\WindowsStore\tools\build-msix.ps1 `
    -PackageVersion "1.0.0.0" `
    -IdentityName "YOUR_PARTNER_CENTER_IDENTITY_NAME" `
    -Publisher "CN=YOUR_PARTNER_CENTER_PUBLISHER" `
    -PublisherDisplayName "YOUR_PARTNER_CENTER_PUBLISHER_DISPLAY_NAME"
```

Replace the identity placeholders with your Partner Center values. Before rebuilding,
remove only the generated `build\store\package` staging directory. The script refuses
to reuse it so stale files cannot accidentally enter a later package. Build outputs
are git-ignored. The committed manifest is a template; do not submit it until the
script has populated the identity.

## Rebuild the artwork

From the repository root on Windows:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\WindowsStore\tools\build-artwork.ps1
```

The process-local execution policy does not change the machine's saved policy.
The script uses Windows' built-in System.Drawing APIs and the original app icon;
it regenerates the three icons and wallpaper without external image dependencies.

## Recapture screenshots

With Godot 4.4.1 or later available as `godot`:

```powershell
godot --headless --path . --editor --import --quit
godot --path . --resolution 1920x1080 --audio-driver Dummy --script res://WindowsStore/tools/capture-screenshots.gd
```

Capture requires a graphical Windows session; do not use `--headless` for the
second command. The helper uses a fixed match seed, advances a real play, and
holds the simulation while the stadium and menus render. It exits after saving
all five images. No production game code or player settings are changed.
