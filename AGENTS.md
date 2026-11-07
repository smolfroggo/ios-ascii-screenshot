# Verification

- `Core/` mirrors tetratorus/ascii-screenshot `macos/Sources/ascii-screen` (without `Live.swift`/`main.swift`); keep changes there minimal and upstream-compatible so history files stay readable by the macOS `ascii-screen`.
- Core tests on macOS: `swift test -c release`. On the iOS Simulator: copy `Package.swift Core Tests` to a directory without `AsciiScreen.xcodeproj`, then `xcodebuild test -scheme AsciiScreenCore -destination 'platform=iOS Simulator,name=iPhone 17'`.
- App: `xcodegen generate`, then `xcodebuild -scheme AsciiScreen -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` (Xcode 27).
- The Simulator has no ScreenCaptureKit: exercise the rest with `xcrun simctl launch booted com.smolfroggo.ascii-screen -readImage <png> -search <query>`. Live capture can only be tested on an iOS 27 device.
