Block App Updates **1.0.3**, featuring improvements contributed by **[ichitaso](https://github.com/ichitaso)** and merged into this project.

### Changes since 1.0.0

## 1.0.3

- Show each application's version next to its name in the Settings list, as in 1.0.0's original design.
- Fall back to the bundle name when an application's display name is empty, fixing applications listed without a name.

## 1.0.2

- Re-register jailbreak, TrollStore and TrollStore Lite applications after the LaunchServices rebuild, fixing apps that stopped launching, lost their icon labels, disappeared or ran letterboxed after committing changes.
- Finish committing as soon as LaunchServices reflects the changed applications instead of always waiting at least 60 seconds (about 15–30 seconds in total on iOS 15-26).
- Restart `appstored` together with App Store so blocked and unblocked applications appear correctly in the update list.

## 1.0.1

- Fit application icons to the Settings list rows.

### Installation

Add **https://sahinkaa.github.io/** to Sileo or Zebra and install or upgrade **Block App Updates**. Your package manager selects the matching architecture.

- **Rootless:** `com.sahinkaa.blockappupdates_1.0.3_iphoneos-arm64.deb`
- **Native RootHide:** `com.sahinkaa.blockappupdates_1.0.3_iphoneos-arm64e.deb`

Both packages target **iOS 15 and later**. Private LaunchServices behavior may vary by iOS version and jailbreak. The new packages have been checked on the build host; this release does not claim additional device testing by sahinkaa.

After installation, follow the package manager's Restart SpringBoard request. When committing changes in Settings, keep the device unlocked until the completion message appears.

### Credits and package provenance

Original development by **sahinkaa**, coded with **OpenAI Codex**. Updates 1.0.1-1.0.3 and native RootHide support by **ichitaso**. Thank you for contributing these fixes and improvements.

These downloads retain ichitaso's published 1.0.3 executable payloads and installer scripts byte-for-byte. Package metadata has been updated for this repository, including **sahinkaa • ichitaso** developer credit and links to the project's package pages. Version and package identifier are unchanged.

Source and the full changelog are included. SHA-256 checksums are supplied for both packages and the dedicated source archive.
