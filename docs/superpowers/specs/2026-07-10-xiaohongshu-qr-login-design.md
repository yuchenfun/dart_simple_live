# Xiaohongshu QR Login Design

## Goal

Add an in-app Xiaohongshu QR login flow for the TV app and the macOS build of the desktop/mobile app. The app displays the official Xiaohongshu QR code, waits for the user to scan and confirm it in the Xiaohongshu mobile app, then saves the resulting web Cookie automatically.

Android and iOS behavior in `simple_live_app` remains unchanged. Windows and Linux desktop support is outside this change.

## Approach

Use an `InAppWebView` to host the official Xiaohongshu login session. After the official page loads, inject JavaScript and CSS that open the login dialog and reduce the visible page to the official QR-code area.

The QR code, scan polling, confirmation, expiration, and final session Cookie therefore remain in one official browser session. The app does not reproduce Xiaohongshu's private QR APIs, request signing, or polling protocol.

Alternatives rejected:

- Extracting the QR code from a headless WebView would separate presentation from a dynamically embedded session and make iframe or canvas changes harder to handle.
- Calling private QR APIs directly would couple the app to undocumented endpoints, signatures, device parameters, and anti-abuse behavior.

## Components

### Shared login-session behavior

Each app receives a Xiaohongshu QR login controller with the same responsibilities:

- Load `https://www.xiaohongshu.com/` with the existing Xiaohongshu desktop user agent.
- Inject the script that opens and isolates the official login dialog.
- Expose loading, ready, failed, expired, and completed states to the page.
- Poll the WebView Cookie manager for `.xiaohongshu.com` login cookies.
- Convert the Cookie collection into the header format already accepted by `XiaohongshuAccountService.setCookie()`.
- Stop polling and release timers when the page is closed or login completes.

Platform UI code may be duplicated where the PC and TV applications already have separate account modules, but Cookie recognition and serialization should be placed in a small testable helper rather than embedded in widget code.

### macOS app

Add a QR login route, page, and controller under the existing Xiaohongshu account module in `simple_live_app`.

The account screen behavior is platform-specific:

- macOS opens the new QR login page.
- Android and iOS retain the existing Xiaohongshu Web login flow.
- Unsupported desktop platforms keep the existing manual Cookie path or unsupported state; this change does not claim QR-login support for them.

### TV app

Add a Xiaohongshu account entry plus a QR login route, page, and controller in `simple_live_tv_app`. The page follows the focus, spacing, and remote-control interaction patterns of the existing Bilibili QR login page while displaying the official Xiaohongshu WebView login region.

### Existing account service

Successful login calls the existing `setCookie()` method. That persists the Cookie, updates `hasCookie`, resets WebView Cookie synchronization state, and refreshes the `XiaohongshuSite` instance. No second Xiaohongshu credential store is introduced.

## Data Flow

1. The user selects Xiaohongshu QR login from the account screen.
2. The controller starts the official WebView session.
3. After page load, the controller injects the login-dialog and layout script.
4. The user scans the displayed official QR code and confirms on the phone.
5. Xiaohongshu completes the login inside that WebView session.
6. The controller reads and validates the resulting Xiaohongshu Cookie set.
7. The controller serializes the cookies and calls `XiaohongshuAccountService.setCookie()`.
8. The page shows a success message and returns to the account screen.

An existing saved Cookie is not deleted when a new login starts. It is replaced only after a new complete login succeeds.

## Login-state Validation

The flow must not treat arbitrary visitor or anti-abuse cookies as a successful login. A pure Dart helper defines the minimum accepted Xiaohongshu login-cookie markers based on the cookies produced by the official login flow and verified during implementation.

The helper accepts a collection of name/value pairs and returns:

- whether the set represents a complete login session;
- a deterministic `name=value; name=value` Cookie header string.

Cookie values are never written to logs, test snapshots, or error messages.

## WebView Presentation

The WebView is part of the visible login page, but injected styling hides the feed, navigation, phone-login controls, and page backdrop. Only the official QR-code card and official scan-status text remain visible and are centered at a readable size.

The injection script should use several bounded selectors and observable fallbacks rather than relying on one deeply nested CSS path. Failure to locate the login region transitions to a retryable error state instead of displaying the unrestricted website.

The TV page provides a remote-focusable reload action. The macOS page provides a standard reload action. Closing either page cancels polling and disposes the WebView session.

## Error Handling

- Page-load failure: show a concise error and a reload action.
- Login dialog or QR region not found before timeout: show a retryable compatibility error.
- Expired QR code: reload the official login region to obtain a new code.
- Partial Cookie set: continue waiting; do not overwrite the saved account.
- Cookie read or persistence failure: keep the page open and offer retry.
- Controller disposal: cancel all timers and ignore late WebView callbacks.

Only a validated Cookie set produces the success toast and automatic navigation back.

## Testing

Add unit tests for the pure Cookie helper:

- visitor cookies do not count as logged in;
- required login cookies count as logged in;
- empty values do not count;
- serialization is deterministic and omits invalid entries;
- Cookie values are preserved without logging or accidental decoding.

Add controller or widget-level tests where the current app test structure permits them:

- successful validation persists through the account service once;
- partial cookies keep the flow pending;
- retry resets failure state and reloads;
- disposal cancels polling;
- macOS and TV account entries resolve to the new route;
- mobile app behavior remains routed to the existing Web login.

Run formatting, focused tests, and static analysis for `simple_live_core`, `simple_live_app`, and `simple_live_tv_app` in proportion to the files changed.

## Commit Scope

The implementation commit includes the QR-login feature and the user's existing modified Xiaohongshu source and test files after they pass verification. Unrelated workspace changes such as editor settings, dependency caches, lockfiles generated under `third_party`, and unrelated tools are excluded.
