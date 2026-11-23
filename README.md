# SHIFTLINE

A tactical roguelite auto-battler built with [LÖVE 2D](https://love2d.org/) for **GitHub Game Off 2026** (Theme: **SHIFT**).

## Concept & Theme: SHIFT

Your entire squad stands on a 6-column frontline facing incoming enemy waves. Instead of micromanaging individual units, you **shift the entire formation left or right** to align attacks, intercept threats, block lane breaches, and trigger positional traits.

- **Pre-battle deployment**: Shift your whole line (`A` / `D`) to line up counters before locking in combat.
- **Mid-battle intervention**: Spend Core Charge or consumable Shift Kits between rounds to reposition when the frontline changes.
- **Camp & progression**: Recruit new units, teach combat traits, upgrade stats, and manage your Act Fuse across 3 escalating Acts.
- **Bilingual UI**: Full English and Simplified Chinese (`简体中文`) support in Settings.

## Controls

| Action | Keyboard | Mouse |
| --- | --- | --- |
| Shift formation left / right | `A` / `D` or `←` / `→` | Click `< A` / `D >` buttons |
| Start round / confirm / strike | `Space` or `Enter` | Click target / Fight button |
| Inspect unit / item | — | Hover or click unit / item |
| Use consumable item | `1` – `4` | Click item slot in top HUD |
| Open route map (in Camp) | `M` | Click Map button |
| Toggle fullscreen | `F11` | — |
| Back / cancel | `Esc` | Click Back |

## Running Locally

Requires [LÖVE 11.4+](https://love2d.org/) (11.5 recommended).

### Windows
```bat
run.bat              :: Launch the game
run.bat --console    :: Launch with console output (lovec)
run.bat --test       :: Run headless test suite (requires luajit)
run.bat --assets     :: Regenerate sprites, icons, and audio (requires node)
run.bat --package    :: Build dist\shift-line.love
```

### Linux / macOS
```bash
./run.sh             # Launch the game
./run.sh --test      # Run headless test suite (requires luajit or nix)
./run.sh --assets    # Regenerate sprites, icons, and audio (requires node)
./run.sh --fonts     # Rebuild CJK font subset (requires node + fonttools/nix)
./run.sh --package   # Build dist/shift-line.love
```

## Automated Builds (GitHub Actions)

The repository includes [`.github/workflows/build.yml`](.github/workflows/build.yml), which automatically runs the full headless test suite and builds:
- **Universal `.love` package** (`shift-line.love`)
- **Windows x64 standalone** (`shift-line-windows-x64.zip`, fused with LÖVE 11.5 and custom `.ico` icon)
- **macOS universal app bundle** (`shift-line-macos.zip`, with custom `.icns` icon)
- **Linux AppImage** (`shift-line-linux-x86_64.AppImage`)
- **Web / HTML5 build for itch.io** (`shift-line-web.zip`, built with `love.js` compatibility mode + OGG-compressed BGM for fast browser loading)

## Credits & Licenses

- **Game Code & Generated Pixel Art / Chiptune Audio**: MIT License (see [`LICENSE`](LICENSE)).
- **Engine**: [LÖVE 2D](https://love2d.org/) (zlib/libpng License).
- **Chinese Pixel Font Subset (`assets/fonts/shiftline-cjk.ttf`)**: Subsetted from [Fusion Pixel Font](https://github.com/TakWolf/fusion-pixel-font) (12px monospaced zh_hans), licensed under the **SIL Open Font License 1.1** (see [`assets/fonts/OFL.txt`](assets/fonts/OFL.txt) and [`assets/fonts/LICENSES/`](assets/fonts/LICENSES/)).
