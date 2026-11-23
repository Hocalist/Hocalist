# Hocalist

Hocalist is a mobile-first reverse marketplace. Buyers post requests, sellers send offers, and buyers select sellers to chat and arrange meetings. Item payment happens offline. Stripe handles platform subscriptions, credits and fees, not buyer-to-seller item payments.

## Source and workflow

Use `staging` for development, then submit a pull request from `staging` to `main`. Pull the latest changes before editing and coordinate changes to shared screens.

- `lib/features/`: buyer and seller screens and flows
- `lib/components/` and `lib/theme/`: shared controls, typography and styling
- `lib/data/` and `lib/domain/`: application data and business models
- `android/` and `ios/`: mobile platform configuration
- `public-web/`: public website and download page
- `admin/`: administration website
- `supabase/` and `database/`: backend functions, migrations and database tests
- `test/`: Flutter tests

Reuse the existing design components and pages when making changes.

## Run the mobile app

Install Flutter and the Android SDK, clone this repository and select `staging`. From the repository root:

```sh
flutter pub get
flutter run
```

Without a public client key, the app runs in prototype mode. To connect to the existing Hocalist backend, copy `client-config.example.json` to `.codex-local/client-config.json` (create the ignored directory if needed). Set `HOCALIST_SUPABASE_PUBLISHABLE_KEY` to the existing project's public client key, then run:

```sh
flutter run --dart-define-from-file=.codex-local/client-config.json
```

The example contains the feature switches used by the current Android test build. Calling remains controlled by the backend and is currently disabled. Never include service-role keys, Stripe secrets or other server credentials in client configuration. Changing the JSON requires restarting the build.

Android maps require the existing restricted Maps key through the `HOCALIST_GOOGLE_MAPS_ANDROID_API_KEY` environment variable or the same property in `android/local.properties`. Keep local configuration and signing credentials out of Git.

## Checks and Android packaging

```sh
flutter analyze
flutter test
flutter build apk --profile --target-platform=android-arm64 --dart-define-from-file=.codex-local/client-config.json
```

The profile APK is an optimized test build, not a Play Store release. Preserve the app package `com.hocalist.app` and the existing signing setup. Production release builds require the configured `HOCALIST_RELEASE_*` signing variables. Android and iOS need their own platform checks; Android proof does not replace iOS testing or signing.

## Android analytics

Use the existing Hocalist Android Firebase registration and its checked-in `android/app/google-services.json`. Analytics follows the app's optional consent setting. `buyer_request_submitted` is recorded after a new request saves; `seller_signup_completed` is recorded after first-time seller profile creation. Login, switching roles and editing an existing profile do not count as signup.

Changing app source does not update an installed APK. Build and publish a new test APK, then update the existing website download metadata when releasing it. Backend migration files require a separate, reviewed application to the existing project; pushing source does not apply them automatically.
