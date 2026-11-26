# mSOUND

## About

mSOUND is a macOS audio tool that merges the fast lossless cut/convert workflow of Fission with the waveform editing of Sound Studio. Right-click any audio file in the Finder to convert it (level-1 menu, no submenu), or open it in a clean waveform editor: cut, copy, paste, markers, normalize, fades, gain, and export. Part of the **DESKTOP MAC TOOLKIT**.

- Convert between MP3, AAC (M4A), FLAC, WAV, AIFF and ALAC; multi-selection of mixed formats to one target format; progress gauge right on the file icon in the Finder.
- Non-destructive editor with unlimited undo, bar-style waveform, overview strip, silence detection.
- Automatic updates from GitHub releases (signature checked). Interface in French, English, Spanish and Italian.
- Requires macOS 14 or later, Apple Silicon. Enable the Finder extension in System Settings › Extensions › Finder.

Inspired by Fission and Sound Studio; not affiliated with Rogue Amoeba or Felt Tip.

## Build

`./build_app.sh` (needs Homebrew `lame` and `mpg123` static libraries). `./release.sh` signs, notarizes and publishes a release.

## Support

If mSOUND is useful to you: https://github.com/sponsors/starbudweiser — optional, nothing is locked.

## License

MIT © 2026 Starbudweiser
