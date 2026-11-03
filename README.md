# Block App Updates

Block updates for selected App Store apps and preserve your Home Screen layout when applying changes.

**Developed by [sahinkaa](https://github.com/sahinkaa)**  
**Coded with Codex**

## Features

- Lists eligible App Store applications in a dedicated Settings pane.
- Keeps applications with blocked updates in a separate **Blocked Updates** section.
- Stages multiple block and unblock selections before applying them together.
- Refreshes the App Store's application information once per commit.
- Saves and restores your Home Screen layout automatically, including folders and icon placement.
- Preserves Sileo's existing notification choice through the refresh.
- Automatically recognizes reinstalled applications and removes obsolete blocked metadata.
- Excludes TrollStore and TrollStore Lite applications.
- Uses a native Settings design with application names, installed versions, bundle identifiers and icons.

## Requirements

- iOS 15 or later
- A rootless or roothide jailbreak
- PreferenceLoader
- arm64 or arm64e device

The package is built for Dopamine-style rootless environments and roothide. Private LaunchServices behavior can vary between jailbreaks and iOS releases.

## Installation

Add [sahinkaa](https://sahinkaa.github.io/) to Sileo or Zebra and install **Block App Updates**. The package manager selects the build for your jailbreak. Both builds are also available from the [GitHub release](https://github.com/sahinkaa/BlockAppUpdates/releases/tag/v1.0.4).

After installation, select **Restart SpringBoard** when prompted and open **Settings → Block App Updates**.

## Usage

1. Tap one or more applications to stage their update status.
2. Tap **Commit** in the navigation bar.
3. Review the confirmation and select **Apply Changes**.
4. Keep the device unlocked until it resprings.

Refreshing the App Store information usually takes 15-30 seconds. The tweak restores your Home Screen layout automatically when SpringBoard restarts.

To allow updates again, select an application under **Blocked Updates** and commit the change.

## How it works

For an application selected for blocking, the tweak renames:

```text
iTunesMetadata.plist → iTunesMetadata_blocked.plist
```

Unblocking restores the original filename. The helper refreshes LaunchServices once per commit, re-registers jailbreak and TrollStore apps then restarts the App Store processes. It saves Sileo's existing Allow or Don't Allow choice before the refresh and restores that entry afterward.

The built-in layout backup uses SpringBoard's own icon store and verifies the restored layout when SpringBoard loads it. This keeps the restored placement across later resprings. If automatic recovery is interrupted, use **Restore Icon Layout** when it appears in Settings.

## Building from source

Install and configure [Theos](https://theos.dev), then run:

```sh
./build.sh
```

This builds both the rootless (`iphoneos-arm64`) and roothide (`iphoneos-arm64e`) packages into `packages/`. To build only one of them:

```sh
make clean package THEOS_PACKAGE_SCHEME=rootless
make clean package THEOS_PACKAGE_SCHEME=roothide
```

The project targets iOS 15 and later and builds arm64 and arm64e binaries.

## Credits

- Developed by **sahinkaa**
- Updates 1.0.1-1.0.3 and native RootHide support by **[ichitaso](https://github.com/ichitaso)**
- Original implementation coded with **Codex**
- LaunchServices refresh behavior inspired by TrollStore's Rebuild Icon Cache workflow

## Disclaimer

Use this software at your own risk. Test it with a non-critical application first. This project is not affiliated with Apple, TrollStore, Dopamine, or Sileo.
