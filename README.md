# MicMuteBar

`MicMuteBar` is a macOS menu bar app for true microphone mute/unmute with a global shortcut.

- Global hotkey: `Cmd+Shift+M`
- Menu bar mic icon + status
- True CoreAudio mute (not “set volume to zero”)
- Optional “mute all mute-capable mics” mode
- Optional built-in “lock input volume to 100 when unmuted” mode
- Launch at login support

## How Muting Works (True Mute)

`MicMuteBar` uses CoreAudio device mute controls (`kAudioDevicePropertyMute`) on input devices.

That means:
- It toggles the microphone device’s actual mute state
- It does **not** fake mute by setting input/output volume to `0`
- It behaves similarly to apps like Mic Drop when the device exposes a writable mute control

The app also verifies the mute state changed after writing. For hardware that exposes mute controls in unusual scopes/channels, it tries multiple CoreAudio mute targets and keeps the one that actually works.

## Modes

### 1. System Default (recommended)

Mutes whichever input device macOS currently has selected as the default input.

### 2. Pinned Microphone

In Settings, select a specific mic to always control that device even if macOS default input changes.

### 3. Mute All Mute-Capable Input Devices

When enabled, the hotkey/menu toggle mutes or unmutes all connected input devices that expose a writable CoreAudio mute control.

This is useful as a “panic mute” if apps switch devices or don’t follow the system default.

## Built-In Volume Lock (Cron Replacement)

`MicMuteBar` includes an optional mode:

- `Lock input volume to 100 when unmuted`

This is intended to replace external scripts/cron jobs that force mic volume to `100`.

Why this matters:
- Some scripts (for example AppleScript `set volume input volume 100`) can interfere with true mute and effectively unmute the mic shortly after you mute it.
- `MicMuteBar`’s built-in volume lock checks mute state first and skips volume writes while muted.

## Requirements / Limitations

- macOS 14+
- Your microphone/interface must expose a writable CoreAudio mute control for true mute
- Some devices support input volume, some do not
- Some apps may use app-specific input devices instead of the system default (use pinned mode or all-mics mode in those cases)

If a device does not support writable CoreAudio mute, the app reports that instead of faking mute.

## Usage

### Menu Bar

- Click the mic icon in the menu bar
- Use `Mute Microphone` / `Unmute Microphone`
- Toggle optional modes:
  - `Mute all mute-capable mics`
  - `Lock mic volume to 100 (when unmuted)`
- Open `Settings...`

### Global Shortcut

- Press `Cmd+Shift+M` anywhere to toggle mute

## Build

```bash
cd MicMuteBar
swift build
```

## Package as `.app`

```bash
./scripts/package_app.sh
open /Applications/MicMuteBar.app
```

The packaging script builds a release binary with SwiftPM and bundles it as:

- `dist/MicMuteBar.app` (staging bundle)
- `/Applications/MicMuteBar.app` (auto-installed by default if writable)

## Launch at Login

The app includes a launch-at-login toggle using `SMAppService`.

Notes:
- It works from the bundled `.app`
- macOS may require approval in System Settings
- The menu/settings UI shows current launch-at-login status

## Troubleshooting

### “It reads mute state but won’t mute”

This usually means the app can read a mute property but the first writable control is not the correct one for your hardware. `MicMuteBar` already includes fallback logic for multiple scopes/channels, which fixes many devices.

### “My mic unmutes shortly after muting”

This is often caused by another process/script forcing input volume changes (for example AppleScript volume scripts).

Use the built-in `Lock input volume to 100 when unmuted` mode instead of an external loop.

### “No mute-capable input devices found”

Your current device(s) may not expose writable CoreAudio mute controls. In that case true mute cannot be forced through this API path.

## Project Notes

- SwiftUI menu bar app (`MenuBarExtra`)
- Carbon global hotkey (`RegisterEventHotKey`)
- CoreAudio for mute/volume control and input device enumeration
