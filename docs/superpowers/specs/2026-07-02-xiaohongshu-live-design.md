# Xiaohongshu Live Platform Design

## Summary

Add Xiaohongshu live support to `simple_live_core`, the main Flutter app, and the TV app. The first release should support room URL parsing, search or discovery where available, room details, playback URLs, local follow refresh, and account Cookie management. Danmaku support is explicitly lower priority: implement it only if the web reverse-engineering work finds stable WebSocket credentials and message formats.

The implementation must stay within the project's current safety boundary: read public live data, play public streams, display danmaku when available, and manage local app state. It must not add official follow/unfollow, payments, gifts, orders, messages, or other account write operations.

## Goals

- Register Xiaohongshu as a supported site in both apps.
- Add a core `XiaohongshuSite` implementation that maps Xiaohongshu web data into existing core models.
- Support playback for known Xiaohongshu live room URLs.
- Support search, category, and recommendation flows when the web endpoints can be reached with anonymous or user-supplied Cookie requests.
- Add account Cookie management in the main app and TV app.
- Include Xiaohongshu Cookie in existing user-controlled account backup and sync flows.
- Keep danmaku optional and non-blocking.

## Non-Goals

- Do not implement official Xiaohongshu account write actions such as follow, unfollow, private messages, shopping, gifts, orders, coupons, or live room interactions.
- Do not make danmaku a blocker for platform availability.
- Do not expose Xiaohongshu raw response structures to app UI code.
- Do not require live network calls in unit tests or CI.

## Architecture

### Core

Add:

- `simple_live_core/lib/src/xiaohongshu_site.dart`
- `simple_live_core/lib/src/danmaku/xiaohongshu_danmaku.dart`

Export both from `simple_live_core/lib/simple_live_core.dart`.

`XiaohongshuSite` will extend or implement `LiveSite` and expose:

- `id = "xiaohongshu"`
- `name = "小红书直播"`
- `cookie`, set by app account services.
- A shared header builder for anonymous and Cookie-authenticated web requests.
- Room detail, playback URL, live status, search, category, and recommendation methods using existing `LiveSite` signatures.

All parsing helpers should remain in core. The apps should only receive existing model types such as `LiveRoomItem`, `LiveRoomDetail`, `LivePlayQuality`, `LivePlayUrl`, and `LiveSearchResult`.

`XiaohongshuDanmaku` should provide the expected `LiveDanmaku` boundary. If stable danmaku transport details are not found, it should close gracefully with a clear "小红书弹幕暂不可用" style message instead of affecting playback.

### Main App

Add:

- `Constant.kXiaohongshu = "xiaohongshu"`
- A `Sites.allSites` entry with logo, display name, and `XiaohongshuSite()`.
- A Xiaohongshu account service similar to `BiliBiliAccountService`.
- A WebView login page similar to the Bilibili web login flow.
- Account page entries for login, logout, Cookie import, Cookie view, and Cookie export.
- URL parsing for stable Xiaohongshu domains and short-link redirects.
- Backup and sync account support for user-controlled Xiaohongshu Cookie transfer.

The account service should:

- Load Cookie from `LocalStorageService` at startup.
- Inject Cookie into `Sites.allSites[Constant.kXiaohongshu]!.liveSite`.
- Save, clear, and expose login state.
- Attempt a lightweight user-info or session validation request if a reliable endpoint is found. If not, a non-empty Cookie is treated as "已配置 Cookie" rather than a verified account identity.
- Clear WebView cookies on logout where the platform supports it.

### TV App

Add matching site registration, constants, local storage keys, account service, settings entry, backup, and sync support.

For login, the TV app should not pretend Xiaohongshu supports the same QR polling flow as Bilibili unless a stable QR endpoint is found. The first TV-friendly account design is:

- Manual Cookie import from settings.
- Account Cookie sync from the main app or WebDAV/profile backup.
- Optional QR or browser-assisted flow only if reverse engineering finds a stable endpoint.

The TV app should support Xiaohongshu search, category/recommendation, playback, and local follow refresh through the shared core implementation.

## Data Flow

### Room Playback

1. User opens a Xiaohongshu room from search, category, follow, history, or parsed URL.
2. The app routes to the existing live room page with `siteId = xiaohongshu` and `roomId`.
3. `LiveRoomController` calls `XiaohongshuSite.getRoomDetail(roomId: roomId)`.
4. Core fetches the web page or API endpoint with shared headers and optional Cookie.
5. Core extracts title, anchor, avatar, cover, online count, live status, canonical URL, and any danmaku arguments discovered during parsing.
6. The controller calls `getPlayQualites(detail: detail)`.
7. The controller calls `getPlayUrls(detail: detail, quality: quality)`.
8. The existing player uses the returned `LivePlayUrl.urls`.
9. `getDanmaku()` starts only when usable danmaku arguments exist.

### Search, Categories, and Recommendation

The implementation should prefer web endpoints or embedded page data that can work with anonymous requests. If endpoints require signed headers, the signing/request construction must be isolated in private core helpers rather than spread across app code.

If one discovery path is blocked by login or risk control, it should fail locally and leave direct room playback available.

### Follow Refresh

Xiaohongshu follows remain local app records. Refresh uses existing follow services and calls `getLiveStatus()` or `getRoomDetail()` for `siteId = xiaohongshu`. The implementation must not call official Xiaohongshu follow or unfollow APIs.

## URL Parsing

The main app should recognize Xiaohongshu live URLs and short links through the existing parse flow. Expected support includes:

- `www.xiaohongshu.com` URLs that contain a stable live room or user live identifier.
- Xiaohongshu short links after HTTP redirect resolution.
- Invalid or non-live Xiaohongshu URLs returning no parse result instead of crashing.

During implementation, the exact regular expressions should be based on observed real web URLs.

## Error Handling

- Missing or expired Cookie: show a login or Cookie configuration prompt when needed, but keep anonymous room parsing available.
- Risk control or signed endpoint failure: return empty discovery results or throw a platform-specific core error. Do not break direct room playback if it still works.
- Room offline: return `LiveRoomDetail.status = false` and no playable URLs.
- Playback URL shape changes: parse multiple likely stream shapes and log the failing stage with a Xiaohongshu prefix.
- Danmaku unavailable: close the danmaku client with a friendly message and keep playback running.
- Short-link resolution failure: return an empty parse result and show the existing parse failure UI.

## Testing

Core unit tests should cover parsing helpers with captured or minimized fixtures:

- Room title and anchor extraction.
- Live status extraction.
- Playback URL and quality extraction.
- Cookie header merge behavior.
- Search or room list mapping where stable fixture data exists.
- Danmaku message decoding only if stable message payloads are found.

App and TV validation should include:

- `dart test` for affected core tests.
- `flutter analyze` for the main app.
- `flutter analyze` for the TV app.
- Manual smoke tests against a small number of live Xiaohongshu URLs after reverse-engineering.

Network-dependent Xiaohongshu checks should not be required for CI because public web responses and risk-control behavior may change.

## Implementation Notes

- Follow the recent Kuaishou implementation for platform registration, core parsing containment, and danmaku isolation.
- Follow Bilibili account services for Cookie injection, login state, and logout behavior.
- Follow the existing Douyin and Kuaishou account flows for manual Cookie import/export where WebView or QR login is not stable.
- Keep site id stable as `xiaohongshu`; it will be persisted in follows, history, sync, and site sorting.
- Ensure the main app site sort migration appends Xiaohongshu for existing users.
- Include both main app and TV app assets and `pubspec.yaml` asset coverage if needed.
