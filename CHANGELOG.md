# Changelog

## 1.0.2

- Re-register jailbreak, TrollStore, and TrollStore Lite applications after the LaunchServices rebuild, fixing apps that stopped launching, lost their icon labels, disappeared, or ran letterboxed after committing changes.
- Finish committing as soon as LaunchServices reflects the changed applications instead of always waiting at least 60 seconds (about 15–30 seconds in total on iOS 15–26).
- Restart `appstored` together with App Store so blocked and unblocked applications appear correctly in the update list.

## 1.0.1

- Fit application icons to the Settings list rows.

## 1.0.0

- Initial public release.
- Selectively blocks and restores App Store updates per application.
- Supports staging multiple changes and applying one LaunchServices refresh.
- Separates blocked updates from available applications.
- Excludes TrollStore-installed applications.
- Detects reinstalled applications and clears obsolete blocked metadata.
- Supports rootless iOS 15 and later on arm64 and arm64e devices.
- Requests Restart SpringBoard after installation, upgrade, and removal.
