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

These are the requested artwork sizes, not a complete MSIX package asset set.
Package manifest logos, scale variants, signing, and any additional images required
by the selected Partner Center submission type must be configured separately. Use
the wallpaper for promotional artwork only, not in the screenshot slots.

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
