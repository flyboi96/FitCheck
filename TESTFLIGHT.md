# FitCheck TestFlight Prep

Use this checklist before sharing FitCheck with another iPhone.

## Before Archiving

- Confirm the bundle ID in Xcode is `com.alexcorbin.personal.FitCheck`.
- Confirm the signing team is your Apple Developer team.
- Confirm `GoogleService-Info.plist` is included in the FitCheck app target.
- Deploy Firestore rules:

```sh
firebase deploy --only firestore:rules
```

- Start or deploy the AI proxy somewhere the real iPhone can reach. `127.0.0.1` only works in the simulator.
- In FitCheck Settings on the phone, set the AI proxy URL to your Mac or server address and set the proxy token.
- Increment the build number for every new upload. This project is currently set to version `1.0`, build `2`.

## Archive and Upload

1. Open `FitCheck.xcodeproj` in Xcode.
2. Select the `FitCheck` scheme.
3. Select `Any iOS Device` or a connected iPhone as the run destination.
4. Choose Product > Archive.
5. In Organizer, validate the archive.
6. Distribute the archive to App Store Connect for TestFlight.
7. In App Store Connect, add the uploaded build to TestFlight testing.
8. Add your wife as a tester and send the invitation.

## Smoke Test on the TestFlight Build

- Register or sign in.
- Upload/download closet metadata.
- Look up weather by current location and by typed city.
- Generate Today, Builder, and Trip outfits.
- Save text feedback.
- Generate an avatar and confirm the preview shows full body from hair or hat through shoes.
- Export and import a backup.
