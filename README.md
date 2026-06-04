# oh-my-display

oh-my-display is a macOS display control project for reading and setting display state.

`omd` is meant to be a practical user-facing CLI: list displays, inspect the current state, list available resolution and display modes, and apply supported changes from scripts or `.command` files.

## Supported Features

- List connected displays and stable selectors.
- Read current display state, including resolution, refresh rate, HiDPI state, display mode, dithering, and ICC profile.
- List display-reported resolution modes, including logical size, backing size, scale, HiDPI state, and refresh rate.
- List display modes, including output timing, refresh rate, encoding, bit depth, range, chroma, and SDR/HDR mode.
- Set resolution modes by exact mode ID or by logical resolution, HiDPI state, and refresh rate.
- Set display modes by exact mode ID or by color properties such as encoding, bit depth, range, chroma, and SDR/HDR mode.
- Set dithering on or off.
- Set a display ICC profile.
- Emit JSON for scripting and automation.

## Requirements

- macOS 14 or newer
- Swift 6 toolchain

Some display properties are backed by public CoreGraphics, ColorSync, and IOKit APIs. Display mode control uses Quartz/CADisplay behavior that is not part of a stable public Apple API surface, so it may vary across macOS releases and display hardware.

## Build

```sh
swift build -c release
```

The executable is written to:

```sh
.build/release/omd
```

Examples below assume `omd` is on your `PATH`. If not, replace `omd` with `.build/release/omd` or `.build/debug/omd`.

For development builds:

```sh
swift build
.build/debug/omd version
```

## Quick Start

List displays:

```sh
omd display list
```

Read the main display state:

```sh
omd display get
```

List available resolution modes for the main display:

```sh
omd display resolutions
```

List available display modes for the main display:

```sh
omd display modes
```

All read commands support JSON output:

```sh
omd display get --json
omd display resolutions --json
omd display modes --json
```

## Display Selection

`--display` defaults to `main` for display-scoped commands:

```sh
omd display get
omd display set --dithering off
```

For scripts that target a specific display, copy a stable selector from:

```sh
omd display list
```

Then pass it explicitly:

```sh
omd display get --display 'uuid:...'
omd display set --display 'uuid:...' --dithering off
```

`--display all` is not supported for mutation.

## Setting Display State

Exact mode IDs are copied from the list commands.

Set an exact resolution mode:

```sh
omd display resolutions
omd display set --resolution-mode '<resolutionMode>' --yes
```

Set an exact display mode:

```sh
omd display modes
omd display set --display-mode '<displayMode>' --yes
```

You can also ask `omd` to resolve a mode from user-facing flags.

Set a resolution by logical size, HiDPI state, and refresh rate:

```sh
omd display set --resolution 1920x1080 --hidpi on --refresh 120 --yes
```

Set display-mode properties for the current timing:

```sh
omd display set --encoding rgb --bpc 10 --range full --chroma 444 --hdr sdr --yes
```

Combine a resolution change with semantic display-mode properties:

```sh
omd display set \
  --resolution 1920x1080 \
  --hidpi on \
  --refresh 120 \
  --encoding rgb \
  --bpc 10 \
  --range full \
  --chroma 444 \
  --hdr sdr \
  --yes
```

Direct settings:

```sh
omd display set --dithering on
omd display set --dithering off
omd display set --icc ~/Library/ColorSync/Profiles/Display.icc
```

When a resolution or display mode may change, non-interactive use requires `--yes`. Interactive terminals prompt before applying the change.

Operations run in this order:

```text
resolution -> displayMode -> dithering -> icc
```

If a later display-mode operation fails after a resolution change, `omd` attempts to restore the original resolution and display mode.

## Command Reference

```text
omd display list [--json]
omd display get [--display <display>] [--json]
omd display resolutions [--display <display>] [--json]
omd display modes [--display <display>] [--json]
omd display set [--display <display>] [set options] [--json] [--yes]
omd version
```

`display set` options:

```text
--resolution-mode <resolutionMode>
--resolution <width>x<height>
--hidpi on|off
--refresh <hz>
--display-mode <displayMode>
--encoding rgb|ycbcr
--bpc <bits-per-component>
--range full|limited
--chroma 444|422|420
--hdr sdr|hdr10
--dithering on|off
--icc <path>
```

Rules:

- `--resolution-mode` cannot be combined with `--resolution`, `--hidpi`, or `--refresh`.
- `--display-mode` cannot be combined with semantic display-mode flags such as `--bpc` or `--hdr`.
- `--display-mode` cannot be combined with a resolution change. Use semantic display-mode flags if the desired display mode should be resolved after the resolution changes.

## Exit Codes

```text
0   success
2   blocked before mutation
3   partial failure after a mutation was attempted
64  usage error
70  unexpected error
```

For automation, prefer `--json`; set commands include per-operation status and whether a mutation was attempted.

## Swift Library

The package also exposes `OMDCore` as a thin Swift library.

```swift
import OMDCore

let displays = try listDisplays()
let display = displays.first { $0.isMain }!

let state = try readDisplayState(display.selector)
let resolutions = try listResolutionModes(display.selector)
let displayModes = try listDisplayModes(display.selector)

let result = try setDithering(display.selector, enabled: false)
```

Public functions:

```swift
listDisplays()
readDisplayState(_:)
listResolutionModes(_:)
setResolutionMode(_:modeID:)
listDisplayModes(_:)
setDisplayMode(_:modeID:)
setDithering(_:enabled:)
setICCProfile(_:profileURL:)
```

The core library intentionally stays thin. Higher-level features such as saved presets should live in a caller layer.

## Testing

```sh
swift test
```

## License

MIT. See [LICENSE](LICENSE).
