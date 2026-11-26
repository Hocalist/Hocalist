# Hocalist USB Marketplace QA

This debug-only setup runs a synthetic marketplace on the computer using the repository’s disposable PostgreSQL test fixture. It exercises the Android request and offer screens over USB, calling the checked-in marketplace database routines. The local service binds to `127.0.0.1`.

1. Install the locked test dependencies in `database/tests` and the Flutter dependencies in the repository root. Flutter must generate its Android plug-in registry before building.
2. Run `node database/tests/usb_qa_server.mjs` on the computer. Set `HOCALIST_USB_QA_PORT` if the default port `48913` is occupied.
3. Run `adb reverse tcp:48913 tcp:48913` for the connected phone. Substitute the selected host port for the second port when using the override.
4. Build in debug mode with `HOCALIST_JONS_DEV=true`, `--dart-define=HOCALIST_USB_QA=true`, and `--dart-define=HOCALIST_SUPABASE_PUBLISHABLE_KEY=sb_publishable_local_hocalist_qa`. Check that the APK package is `com.hocalist.app.jonsdev` before installing.
5. Use the synthetic buyer and seller credentials defined in the server fixture. Inspect `http://127.0.0.1:48913/__qa/state` on the computer to verify request statuses and offer values. The fixture recreates its synthetic records when restarted.

The development server implements the auth and database endpoints used by the tested flows. External payments, OAuth, push delivery, calls, and full meeting and PIN workflows require a separately configured staging environment. Do not deploy this fixture or add it to a release pull request.
