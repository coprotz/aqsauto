# QS Smart

QS Smart is a Flutter quantity surveying take-off platform. It supports
projects, buildings, drawing uploads, drawing calibration, measurement
capture, BOQ management, templates, Excel workflows, and linked quantities.

## Architecture

- `lib/`: Flutter application
- `functions/`: Firebase Cloud Functions
- `aqssite-files-gateway/`: Cloudflare Worker for R2 file access
- `test/`: Flutter unit and widget tests

The application currently uses Firebase Authentication, Firestore, Firebase
Storage, Cloud Functions, and Cloudflare R2.

## Flutter Setup

Use Flutter compatible with Dart `^3.7.2`. Firebase Functions use Node.js 22.
Install Node dependencies with `npm ci` in the repository root, `functions/`,
and `aqssite-files-gateway/` when working on those components.

Firebase client configuration identifies the Firebase project; it does not
replace Firestore/Storage security rules. Review the configured project before
running the app, and use emulators for tests that would modify live records.
Obtain private environment values from the project owner. The Functions
environment variable names are documented in `functions/.env.example`.

Install dependencies:

```sh
flutter pub get
```

R2 uploads can be enabled with build-time configuration:

```sh
flutter run \
  --dart-define=AQS_FILES_GATEWAY_URL=https://your-worker.example.com \
  --dart-define=AQS_FILES_UPLOAD_TOKEN=your-upload-token
```

`AQS_FILES_GATEWAY_URL` has a default value. The upload token has no default
and must not be committed to source control. When no R2 upload token is
provided, drawing uploads automatically use authenticated Firebase Storage.

Run checks:

```sh
flutter analyze
flutter test
```

## File Gateway

Install and test:

```sh
cd aqssite-files-gateway
npm install
npm test
```

Configure the Worker upload secret before deployment:

```sh
npx wrangler secret put UPLOAD_TOKEN
```

Deploy:

```sh
npm run deploy
```

## Development Priorities

1. Stabilize the project, drawing, calibration, measurement, BOQ, and export
   workflow.
2. Split the take-off controller into focused domain services.
3. Consolidate duplicate legacy and GetX screens.
4. Add formula, BOQ import, Firebase emulator, and workflow tests.
5. Replace the shared R2 upload token with short-lived, user-authorized upload
   credentials before production use.

## Git and private backups

Keep this repository private. Review `git diff --cached` before each commit.
Never commit service-account credentials, signing keys, real `.env` files,
upload tokens, customer exports or generated reports. Ignored files remain on
the computer and need a separate secure backup if they are important.

Commit application source, assets, platform project files, tests and lockfiles.
Dependencies and build output are regenerated from those files.
Git backs up source code, not Firestore records or uploaded drawings.
No deployment is required to create or push a source-code backup.
