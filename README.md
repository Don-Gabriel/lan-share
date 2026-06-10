# LAN Share

LAN Share is a Flutter app for sending files and folders directly between
devices on the same local network.

## Current Features

- LAN device discovery with app/protocol validation.
- Manual IPv4 connect when network broadcast is blocked.
- File and folder transfer over TCP.
- Android file selection uses URI streaming so large files appear immediately.
- Batch queue progress with per-file progress, speed, and ETA.
- SHA-256 verification after receive.
- Safe receive-path sanitization for peer-provided file names and folders.
- Mutual trusted-device tracking after accepting a transfer.
- Persistent transfer history for sent and received transfers.

## Development Checks

Run these from this folder:

```powershell
flutter pub get
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter run
```

`flutter run` starts the app for local testing. It does not create a release APK
or Windows build artifact.
