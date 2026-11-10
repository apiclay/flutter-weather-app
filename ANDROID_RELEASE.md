# Android release preparation

The tutorial validates local Android development. It does not publish a Play Store release.

1. Deploy the backend behind HTTPS with user authentication and per-user abuse controls. Keep the ApiClay token on that server. A local 30-call budget is not production security.
2. Choose a unique Android application ID, icon, version and privacy policy appropriate to your app. Review the data provider and content licenses separately from this repository's MIT license.
3. Create and securely back up your own upload keystore. Keep the keystore, passwords and `android/key.properties` outside GitHub. Configure release signing as described in the official Flutter guide.
4. Use your HTTPS backend URL when building: `flutter build appbundle --release --dart-define=API_BASE_URL=https://YOUR_BACKEND_HOST`.
5. Test the signed bundle on Google's internal testing track, complete the store listing and required policy/data declarations, then submit for review. Approval is separate from creating an app.

Official instructions, checked 2026-11-09: [Flutter Android deployment](https://docs.flutter.dev/deployment/android).
