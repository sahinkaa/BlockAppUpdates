# Changelog

## 1.0.0

- Initial public release.
- Selectively blocks and restores App Store updates per application.
- Supports staging multiple changes and applying one LaunchServices refresh.
- Separates blocked updates from available applications.
- Excludes TrollStore-installed applications.
- Detects reinstalled applications and clears obsolete blocked metadata.
- Supports rootless iOS 15 and later on arm64 and arm64e devices.
- Requests Restart SpringBoard after installation, upgrade, and removal.
