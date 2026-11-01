# Block App Updates

Block updates for selected App Store applications without disabling updates for everything else.

**Developed by [sahinkaa](https://github.com/sahinkaa)**  
**Coded with Codex**

## Features

- Lists eligible App Store applications in a dedicated Settings pane.
- Keeps applications with blocked updates in a separate **Blocked Updates** section.
- Stages multiple block and unblock selections before applying them together.
- Refreshes the App Store's application information once per commit.
- Automatically recognizes reinstalled applications and removes obsolete blocked metadata.
- Excludes TrollStore and TrollStore Lite applications.
- Uses a native Settings design with application names, bundle identifiers, and icons.

## Requirements

- iOS 15 or later
- A rootless jailbreak
- PreferenceLoader
- arm64 or arm64e device

The package is built primarily for Dopamine-style rootless environments. Private LaunchServices behavior can vary between jailbreaks and iOS releases.

## Installation

1. Download `com.sahinkaa.blockappupdates_1.0.0_iphoneos-arm64.deb` from the latest GitHub release.
2. Open the package in Sileo or another compatible package manager.
3. Install it and select **Restart SpringBoard**.
4. Open **Settings → Block App Updates**.

## Usage

1. Tap one or more applications to stage their update status.
2. Tap **Commit** in the navigation bar.
3. Review the confirmation and select **Apply Changes**.
4. Keep the device unlocked until the completion message appears.

Refreshing the App Store information normally takes 15–30 seconds. Keep the device unlocked until the completion message appears.

To allow updates again, select an application under **Blocked Updates** and commit the change.

## How it works

For an application selected for blocking, the tweak renames:

```text
iTunesMetadata.plist → iTunesMetadata_blocked.plist
```

Unblocking restores the original filename. After committing, a privileged helper requests one LaunchServices database refresh so the App Store reloads the application's installed state. Because that rebuild only restores applications known to installd, the helper then re-registers jailbreak applications (`uicache -p`) and TrollStore / TrollStore Lite applications (their own `trollstorehelper refresh`, the same as **Refresh App Registrations**), and finally restarts App Store and `appstored` so the update list is reloaded.

The tweak does not globally disable automatic updates, delete the icon cache, or respring after every change. TrollStore applications are ignored because they do not use normal App Store metadata.

## Building from source

Install and configure [Theos](https://theos.dev), then run:

```sh
make clean package FINALPACKAGE=1
```

The project targets rootless iOS 15 and later and builds arm64 and arm64e binaries.

## Credits

- Developed by **sahinkaa**
- Coded with **Codex**
- LaunchServices refresh behavior inspired by TrollStore's Rebuild Icon Cache workflow

## Disclaimer

Use this software at your own risk. Test it with a non-critical application first. This project is not affiliated with Apple, TrollStore, Dopamine, or Sileo.
