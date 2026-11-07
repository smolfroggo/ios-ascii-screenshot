# ASCII Screen for iOS

An iOS 27 port of [tetratorus/ascii-screenshot](https://github.com/tetratorus/ascii-screenshot). It keeps a text copy of the iPhone screen, about once a second: text where it sits on screen, UI boxes and rules drawn as `_` and `|`, plus a compressed, searchable history. OCR runs on the phone with Apple Vision. There is no network code, and no jailbreak is needed.

## How it works

1. **Start capturing** opens the system screen-sharing picker (ScreenCaptureKit's `SCContentSharingPicker`, new in iOS 27). Choose the entire screen.
2. `SCStream` delivers frames. iOS doesn't offer `minimumFrameInterval`, `queueDepth` or `pixelFormat` (macOS-only), so `FrameProcessor`:
   - keeps only the newest complete frame;
   - copies it into an app-owned BGRA buffer with `VTPixelTransferSession`;
   - processes it from a 1 s timer.
3. `Core/` is the macOS service's pipeline, unchanged. It diffs against the previous frame, re-reads only the changed tiles (packed into one Vision call), follows scrolls, and detects lines. A pixel-identical frame is skipped.
4. Changed frames go to `Documents/history/YYYY-MM-DD.txt.gz` with an SQLite FTS5 `index.sqlite`, the same format as `~/.ascii-screen/history` on macOS. Search works in the app. The folder is visible in the Files app, and `ascii-screen --at` / `--play` / `--search` on a Mac read it when copied to `~/.ascii-screen/history`.

| | macOS service | iOS app |
| --- | --- | --- |
| Start | LaunchAgent at login | user taps Start and picks the screen in the system picker |
| 1 frame/sec | `minimumFrameInterval` | app timer, newest frame wins |
| Pixel format | BGRA requested | system format, converted to BGRA |
| Cursor | drawn | none (touch has no pointer) |
| Capture scale | `--scale`, default 1x points | picker 1x/2x/3x, default 2x (3x = native pixels) |

## Build

Needs Xcode 27 and an iOS 27 device. The iOS Simulator SDK has no ScreenCaptureKit, so live capture only works on hardware.

```sh
brew install xcodegen
xcodegen generate && open AsciiScreen.xcodeproj   # set your team, run on the device
```

The Run scheme uses Release: the per-pixel diff and line detector are far too slow unoptimized.

In the Simulator you can still exercise the pipeline, history and search: "Read a screenshot…", or

```sh
xcrun simctl launch booted com.smolfroggo.ascii-screen -readImage /path/shot.png -search "some words"
```

## Tests

`Core/` and `Tests/` are tetratorus/ascii-screenshot's `macos/Sources` (minus `Live.swift` and `main.swift`) and its tests.

```sh
swift test -c release                                 # macOS
# iOS Simulator (run from a directory without the generated .xcodeproj):
xcodebuild test -scheme AsciiScreenCore -destination 'platform=iOS Simulator,name=iPhone 17'
```
