# Changelog

## 1.0.5

- Preserve the existing Allow or Don't Allow notification choice of all jailbreak, TrollStore and TrollStore Lite apps after the App Store refresh, not only Sileo's.
- Ask to restore the previous Home Screen layout before showing the confirmation, instead of after **Apply Changes** is selected.
- Trim stray whitespace from helper messages shown in alerts.
- Set the helper's setuid bit and the installer scripts' permissions while packaging, so `make package` alone produces a correct package. Remove `normalize_package.py` and simplify `build.sh`.

## 1.0.4

- Automatically save and restore Home Screen folders and icon placement when applying changes. The restored layout persists across later resprings.
- Preserve Sileo's existing notification choice after the App Store refresh so it does not ask again.
- Shorten the confirmation and show that the device will respring when the refresh is complete.

## 1.0.3

- Show each application's version next to its name in the Settings list, as in 1.0.0's original design.
- Fall back to the bundle name when an application's display name is empty, fixing applications listed without a name.

## 1.0.2

- Re-register jailbreak, TrollStore and TrollStore Lite applications after the LaunchServices rebuild, fixing apps that stopped launching, lost their icon labels, disappeared or ran letterboxed after committing changes.
- Finish committing as soon as LaunchServices reflects the changed applications instead of always waiting at least 60 seconds (about 15–30 seconds in total on iOS 15-26).
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
- Requests Restart SpringBoard after installation, upgrade and removal.
