# Nintendo DS in Madeira Dev

The middle tab between Windows and Settings runs Nintendo DS `.nds` games
with the [melonDS DS](https://github.com/JesseTG/melonds-ds) libretro core.
It is a separate native session: it does not use Wine, Steam, or JIT.

## Playing

1. Open the Nintendo DS tab and choose **Import .nds game**. Select a ROM you
   are entitled to use. Madeira copies it to `Files → On My iPad/iPhone →
   Madeira Dev → Nintendo DS → Games`. You can also place `.nds` files in that
   folder directly and reopen the tab.
2. Tap the game. The top and bottom DS screens appear together. Touch the
   lower screen for stylus input. The onscreen D-pad, A/B/X/Y, L/R,
   Start/Select, and a connected game controller provide the other buttons.
3. Tap **Done** to close the session. Battery saves are written periodically
   and on exit to `Nintendo DS/Saves/<ROM name>.srm`. Removing a game from the
   list leaves its save file in place.

The core has built-in DS BIOS and firmware replacements. If a game needs your
own system files, place them in `Nintendo DS/System/melonDS DS/`; the upstream
[system-file guide](https://github.com/JesseTG/melonds-ds#installing-nintendo-ds-bios)
describes their names. Madeira does not ship ROMs or Nintendo firmware. This
first integration accepts `.nds` cartridges; DSi software and save states are
not yet exposed in the UI.

Games designed to be held like a book currently appear sideways. An in-app
screen rotation control is not yet available.

## Device verification

On an iPad Air M3 running iPadOS 27.0.1, the open-source `micrecord` test ROM
and a commercial DS cartridge both displayed game frames after the video
surface was changed to a SwiftUI-observed image. The commercial title's menu,
onscreen buttons, touch input, and audio were confirmed working. The earlier
black screen came from a UIKit video view with zero bounds and no window even
though the core was producing frames. Core logs are kept on device in
`Nintendo DS/Logs/core.log` and reset when a game starts.

## Building and licensing

Run `build/melonds-ds/build.sh` before the Xcode build. It fetches the
`v1.4.0` source at commit `f394adbacb5722ee97c1b37c8064da9a25818310`,
builds an iOS ARM64 shared libretro core with JIT and OpenGL disabled, and
copies the result into `app/Madeira/NintendoDS/melondsds_libretro.dylib`.
The dylib and fetched source/build trees are ignored by Git. The Xcode target
embeds and signs the dylib in `Frameworks`; a missing dylib fails the build.

melonDS DS is GPL-3.0, and the bundled libretro API header is MIT. Their
license texts are included in `app/Madeira/legal/`. When distributing a
modified app, provide the corresponding source and build instructions along
with the existing Madeira license materials. No BIOS or ROM is included.
