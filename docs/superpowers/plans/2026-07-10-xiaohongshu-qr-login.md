# Xiaohongshu QR Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display Xiaohongshu's official QR login inside the TV app and the macOS app, then automatically persist the authenticated Web Cookie.

**Architecture:** A pure helper in `simple_live_core` validates and serializes Xiaohongshu cookies. Each app owns a small GetX controller and page around `InAppWebView`; the official page owns QR generation and polling, while Dart only isolates the login UI and observes the resulting Cookie jar.

**Tech Stack:** Dart, Flutter, GetX, `flutter_inappwebview` 6.1.5, `flutter_smart_dialog`, `flutter_test`/`test`.

## Global Constraints

- Support `simple_live_tv_app` and macOS in `simple_live_app` only.
- Keep Android and iOS Xiaohongshu Web login behavior unchanged.
- Do not claim Windows or Linux QR-login support.
- Use the official Xiaohongshu WebView session; do not call private QR APIs directly.
- Do not delete a saved Cookie until a replacement login succeeds.
- Never log Cookie names and values as a complete credential string.
- Exclude `.vscode`, `third_party` generated files, and unrelated tools from feature commits.

---

## File Map

- Create `simple_live_core/lib/src/common/xiaohongshu_cookie_helper.dart`: pure login-marker validation and deterministic Cookie serialization.
- Create `simple_live_core/test/xiaohongshu_cookie_helper_test.dart`: helper contract tests.
- Modify `simple_live_core/lib/simple_live_core.dart`: export the shared helper.
- Create `simple_live_app/lib/modules/mine/account/xiaohongshu/qr_login_controller.dart`: macOS WebView lifecycle, UI injection, Cookie polling, and persistence.
- Create `simple_live_app/lib/modules/mine/account/xiaohongshu/qr_login_page.dart`: macOS login page.
- Create `simple_live_app/test/modules/mine/account/xiaohongshu/qr_login_controller_test.dart`: macOS controller state and persistence tests.
- Modify `simple_live_app/lib/routes/route_path.dart`: macOS QR route constant.
- Modify `simple_live_app/lib/routes/app_pages.dart`: macOS QR page and binding.
- Modify `simple_live_app/lib/modules/mine/account/account_controller.dart`: route macOS users to QR login.
- Modify `simple_live_app/lib/modules/mine/account/account_page.dart`: show the macOS QR action label.
- Create `simple_live_tv_app/lib/modules/account/xiaohongshu/qr_login_controller.dart`: TV WebView lifecycle, UI injection, Cookie polling, and persistence.
- Create `simple_live_tv_app/lib/modules/account/xiaohongshu/qr_login_page.dart`: TV-sized login surface and remote-focusable retry action.
- Create `simple_live_tv_app/test/modules/account/xiaohongshu/qr_login_controller_test.dart`: TV controller state and idempotency tests.
- Modify `simple_live_tv_app/lib/routes/route_path.dart`: TV QR route constant.
- Modify `simple_live_tv_app/lib/routes/app_pages.dart`: TV QR page and binding.
- Modify `simple_live_tv_app/lib/modules/settings/settings_controller.dart`: TV login/clear action.
- Modify `simple_live_tv_app/lib/modules/settings/settings_page.dart`: TV Xiaohongshu account tile.

### Task 1: Shared Xiaohongshu Cookie Contract

**Files:**
- Create: `simple_live_core/lib/src/common/xiaohongshu_cookie_helper.dart`
- Create: `simple_live_core/test/xiaohongshu_cookie_helper_test.dart`
- Modify: `simple_live_core/lib/simple_live_core.dart`

**Interfaces:**
- Consumes: `Map<String, String>` from `WebViewCookieManager.getCookies()`.
- Produces: `XiaohongshuCookieHelper.isLoggedIn(Map<String, String>) -> bool` and `XiaohongshuCookieHelper.serialize(Map<String, String>) -> String`.

- [ ] **Step 1: Write the failing helper tests**

```dart
import 'package:simple_live_core/simple_live_core.dart';
import 'package:test/test.dart';

void main() {
  group('XiaohongshuCookieHelper', () {
    test('visitor cookies are not a login session', () {
      expect(
        XiaohongshuCookieHelper.isLoggedIn({'a1': 'visitor', 'webId': 'id'}),
        isFalse,
      );
    });

    test('a non-empty web_session is a login session', () {
      expect(
        XiaohongshuCookieHelper.isLoggedIn({'web_session': 'session-value'}),
        isTrue,
      );
      expect(XiaohongshuCookieHelper.isLoggedIn({'web_session': '  '}), isFalse);
    });

    test('serialization is deterministic and skips invalid entries', () {
      expect(
        XiaohongshuCookieHelper.serialize({
          'web_session': 'abc==',
          '': 'ignored',
          'a1': 'visitor',
          'empty': '',
        }),
        'a1=visitor; web_session=abc==',
      );
    });
  });
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `cd simple_live_core && dart test test/xiaohongshu_cookie_helper_test.dart`

Expected: compilation fails because `XiaohongshuCookieHelper` is undefined.

- [ ] **Step 3: Implement the pure helper and export it**

```dart
class XiaohongshuCookieHelper {
  static bool isLoggedIn(Map<String, String> cookies) {
    return (cookies['web_session'] ?? '').trim().isNotEmpty;
  }

  static String serialize(Map<String, String> cookies) {
    final entries = cookies.entries
        .where((entry) => entry.key.trim().isNotEmpty && entry.value.isNotEmpty)
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
  }
}
```

Add this export to `simple_live_core/lib/simple_live_core.dart`:

```dart
export 'src/common/xiaohongshu_cookie_helper.dart';
```

- [ ] **Step 4: Run tests and verify GREEN**

Run: `cd simple_live_core && dart test test/xiaohongshu_cookie_helper_test.dart`

Expected: all three tests pass.

- [ ] **Step 5: Commit the helper**

```bash
git add simple_live_core/lib/simple_live_core.dart \
  simple_live_core/lib/src/common/xiaohongshu_cookie_helper.dart \
  simple_live_core/test/xiaohongshu_cookie_helper_test.dart
git commit -m "Add Xiaohongshu login cookie helper"
```

### Task 2: macOS QR Login Controller and Page

**Files:**
- Create: `simple_live_app/lib/modules/mine/account/xiaohongshu/qr_login_controller.dart`
- Create: `simple_live_app/lib/modules/mine/account/xiaohongshu/qr_login_page.dart`

**Interfaces:**
- Consumes: `XiaohongshuCookieHelper`, `XiaohongshuAccountService.setCookie(String)`, `InAppWebViewController`, and `WebViewCookieManager`.
- Produces: `XiaohongshuQRLoginController.status`, `attachController`, `handleLoadStop`, `handleLoadError`, and `reload` for the page.

- [ ] **Step 1: Add a controller test seam before WebView code**

Define the state and injectable cookie reader so Cookie completion can be tested without a platform WebView:

```dart
enum XiaohongshuQRLoginStatus { loading, waiting, failed, completed }

typedef XiaohongshuCookieReader = Future<Map<String, String>> Function();
typedef XiaohongshuCookieSaver = void Function(String cookie);

class XiaohongshuQRLoginController extends GetxController {
  XiaohongshuQRLoginController({
    XiaohongshuCookieReader? cookieReader,
    XiaohongshuCookieSaver? cookieSaver,
  })  : _cookieReader = cookieReader,
        _cookieSaver = cookieSaver;

  final XiaohongshuCookieReader? _cookieReader;
  final XiaohongshuCookieSaver? _cookieSaver;
  final status = XiaohongshuQRLoginStatus.loading.obs;
  final errorMessage = ''.obs;
}
```

Create `simple_live_app/test/modules/mine/account/xiaohongshu/qr_login_controller_test.dart` with a test that injects `{'web_session': 'signed-in'}`, calls the public `checkLoginForTest()` once, and expects `completed` plus the saved string `web_session=signed-in`.

- [ ] **Step 2: Run the controller test and verify RED**

Run: `cd simple_live_app && flutter test test/modules/mine/account/xiaohongshu/qr_login_controller_test.dart`

Expected: failure because `checkLoginForTest()` and completion behavior are not implemented.

- [ ] **Step 3: Implement WebView lifecycle and polling**

Use a two-second periodic timer, guard completion with `_completed`, and expose the same private check through `@visibleForTesting`:

```dart
Timer? _pollTimer;
InAppWebViewController? webViewController;
bool _completed = false;

Future<void> checkLoginForTest() => _checkLogin();

Future<void> _checkLogin() async {
  if (_completed) return;
  final cookies = _cookieReader != null
      ? await _cookieReader!()
      : {
          for (final item in await WebViewCookieManager.instance().getCookies(
            url: WebUri('https://www.xiaohongshu.com/'),
          ))
            item.name: item.value,
        };
  if (!XiaohongshuCookieHelper.isLoggedIn(cookies)) return;
  _completed = true;
  _pollTimer?.cancel();
  final value = XiaohongshuCookieHelper.serialize(cookies);
  (_cookieSaver ?? XiaohongshuAccountService.instance.setCookie)(value);
  status.value = XiaohongshuQRLoginStatus.completed;
  SmartDialog.showToast('小红书登录成功');
  if (_cookieSaver == null) Get.back(result: true);
}
```

`handleLoadStop` injects the official-page isolation script, changes status to `waiting`, and starts polling. `handleLoadError` cancels polling and sets `failed`. `reload` returns to `loading` and reloads the official URL. `onClose` always cancels the timer.

Use this bounded JavaScript shape in a Dart raw string; it must never reveal the unrestricted feed if login UI cannot be located:

```javascript
(() => {
  const clickLogin = () => {
    const nodes = [...document.querySelectorAll('button, [role="button"]')];
    const login = nodes.find((node) => node.textContent.trim() === '登录');
    if (login) login.click();
  };
  clickLogin();
  const style = document.createElement('style');
  style.textContent = `
    body > * { visibility: hidden !important; }
    iframe, iframe * { visibility: visible !important; }
    iframe { position: fixed !important; inset: 0 !important;
      width: 100vw !important; height: 100vh !important; border: 0 !important; }
  `;
  document.head.appendChild(style);
  return Boolean(document.querySelector('iframe'));
})()
```

- [ ] **Step 4: Build the macOS page**

Create a `Scaffold` titled `小红书扫码登录`. Its body is a `Stack` containing the `InAppWebView` and an `Obx` overlay. Configure:

```dart
initialUrlRequest: URLRequest(url: WebUri('https://www.xiaohongshu.com/')),
initialSettings: InAppWebViewSettings(
  userAgent: XiaohongshuSite.userAgent,
  javaScriptEnabled: true,
  transparentBackground: false,
),
onWebViewCreated: controller.attachController,
onLoadStop: controller.handleLoadStop,
onReceivedError: controller.handleLoadError,
```

Show a progress indicator for `loading`, no blocking overlay for `waiting`, and a centered error plus `重新加载` button for `failed`. Add the fixed instruction `请使用小红书手机客户端扫码并确认登录` below the WebView.

- [ ] **Step 5: Run focused tests, analyze, and commit**

Run:

```bash
cd simple_live_app
flutter test test/modules/mine/account/xiaohongshu/qr_login_controller_test.dart
flutter analyze lib/modules/mine/account/xiaohongshu/qr_login_controller.dart \
  lib/modules/mine/account/xiaohongshu/qr_login_page.dart
```

Expected: tests pass and analysis reports no issues.

```bash
git add simple_live_app/lib/modules/mine/account/xiaohongshu/qr_login_controller.dart \
  simple_live_app/lib/modules/mine/account/xiaohongshu/qr_login_page.dart \
  simple_live_app/test/modules/mine/account/xiaohongshu/qr_login_controller_test.dart
git commit -m "Add macOS Xiaohongshu QR login page"
```

### Task 3: Wire macOS Routing and Account Entry

**Files:**
- Modify: `simple_live_app/lib/routes/route_path.dart`
- Modify: `simple_live_app/lib/routes/app_pages.dart`
- Modify: `simple_live_app/lib/modules/mine/account/account_controller.dart`
- Modify: `simple_live_app/lib/modules/mine/account/account_page.dart`

**Interfaces:**
- Consumes: `XiaohongshuQRLoginPage` and `XiaohongshuQRLoginController` from Task 2.
- Produces: `RoutePath.kXiaohongshuQRLogin` and a macOS-visible account action.

- [ ] **Step 1: Add the route constant and page binding**

```dart
/// 小红书二维码登录
static const kXiaohongshuQRLogin =
    '/settings/account/xiaohongshu/qr_login';
```

Register it next to the existing Xiaohongshu Web-login route:

```dart
GetPage(
  name: RoutePath.kXiaohongshuQRLogin,
  page: () => const XiaohongshuQRLoginPage(),
  bindings: [
    BindingsBuilder.put(() => XiaohongshuQRLoginController()),
  ],
),
```

- [ ] **Step 2: Add the macOS account action without changing mobile behavior**

Add:

```dart
bool get canUseXiaohongshuQRLogin => Platform.isMacOS;

void xiaohongshuQRLogin() {
  Get.toNamed(RoutePath.kXiaohongshuQRLogin);
}
```

In `xiaohongshuLogin()`, insert a `Platform.isMacOS` option titled `扫码登录`, then retain the existing Android/iOS Web-login option and manual Cookie option. Change the account-list trailing widget to a `扫码登录` button on macOS, a `网页登录` button on Android/iOS, and the existing chevron elsewhere.

- [ ] **Step 3: Format, analyze, and commit the macOS integration**

Run:

```bash
dart format simple_live_app/lib/routes/route_path.dart \
  simple_live_app/lib/routes/app_pages.dart \
  simple_live_app/lib/modules/mine/account/account_controller.dart \
  simple_live_app/lib/modules/mine/account/account_page.dart
cd simple_live_app
flutter analyze lib/routes lib/modules/mine/account
```

Expected: analysis reports no issues introduced by the route or account entry.

```bash
git add simple_live_app/lib/routes/route_path.dart \
  simple_live_app/lib/routes/app_pages.dart \
  simple_live_app/lib/modules/mine/account/account_controller.dart \
  simple_live_app/lib/modules/mine/account/account_page.dart
git commit -m "Wire macOS Xiaohongshu QR login"
```

### Task 4: TV QR Login Controller and Page

**Files:**
- Create: `simple_live_tv_app/lib/modules/account/xiaohongshu/qr_login_controller.dart`
- Create: `simple_live_tv_app/lib/modules/account/xiaohongshu/qr_login_page.dart`

**Interfaces:**
- Consumes: `XiaohongshuCookieHelper`, TV `XiaohongshuAccountService`, and TV focus widgets.
- Produces: `XiaohongshuQRLoginController` and `XiaohongshuQRLoginPage` for TV routing.

- [ ] **Step 1: Write the TV controller test first**

Create `simple_live_tv_app/test/modules/account/xiaohongshu/qr_login_controller_test.dart`. Inject a cookie reader returning only `a1` and assert the public test seam leaves status at `waiting`; inject `web_session` and assert exactly one save when the seam is called twice.

```dart
expect(controller.status.value, XiaohongshuQRLoginStatus.waiting);
await controller.checkLoginForTest();
await controller.checkLoginForTest();
expect(savedCookies, ['web_session=signed-in']);
expect(controller.status.value, XiaohongshuQRLoginStatus.completed);
```

- [ ] **Step 2: Run the TV test and verify RED**

Run: `cd simple_live_tv_app && flutter test test/modules/account/xiaohongshu/qr_login_controller_test.dart`

Expected: compilation fails because the TV controller does not exist.

- [ ] **Step 3: Implement the TV controller with the same shared contract**

Implement the same state enum, injected test seams, two-second timer, bounded injection script, Cookie manager read, `_completed` guard, and `onClose` cancellation used by the macOS controller. The only app-specific persistence line is:

```dart
(_cookieSaver ?? XiaohongshuAccountService.instance.setCookie)(value);
```

Do not copy or log the completed Cookie anywhere else.

- [ ] **Step 4: Build the TV page using TV-native focus controls**

Create an `AppScaffold` page with the existing back-button/header layout. Put the WebView in a centered `SizedBox` sized for the TV viewport. For failure state, use a `HighlightButton` with a fresh `AppFocusNode`, `Icons.refresh`, text `重新加载`, and `controller.reload`. Display `请使用小红书手机客户端扫码并确认登录` using the existing 32-scaled text style.

The WebView callbacks and settings match Task 2 exactly so both apps host the same official flow.

- [ ] **Step 5: Run focused tests, analyze, and commit**

Run:

```bash
cd simple_live_tv_app
flutter test test/modules/account/xiaohongshu/qr_login_controller_test.dart
flutter analyze lib/modules/account/xiaohongshu
```

Expected: tests pass and analysis reports no issues.

```bash
git add simple_live_tv_app/lib/modules/account/xiaohongshu \
  simple_live_tv_app/test/modules/account/xiaohongshu/qr_login_controller_test.dart
git commit -m "Add TV Xiaohongshu QR login page"
```

### Task 5: Wire TV Routing and Account Settings

**Files:**
- Modify: `simple_live_tv_app/lib/routes/route_path.dart`
- Modify: `simple_live_tv_app/lib/routes/app_pages.dart`
- Modify: `simple_live_tv_app/lib/modules/settings/settings_controller.dart`
- Modify: `simple_live_tv_app/lib/modules/settings/settings_page.dart`

**Interfaces:**
- Consumes: TV QR page/controller from Task 4 and `XiaohongshuAccountService.hasCookie`.
- Produces: `RoutePath.kXiaohongshuQRLogin`, TV route binding, and account settings tile.

- [ ] **Step 1: Register the TV route**

```dart
/// 小红书二维码登录
static const kXiaohongshuQRLogin = '/xiaohongshu/qr_login';
```

```dart
GetPage(
  name: RoutePath.kXiaohongshuQRLogin,
  page: () => const XiaohongshuQRLoginPage(),
  bindings: [
    BindingsBuilder.put(() => XiaohongshuQRLoginController()),
  ],
),
```

- [ ] **Step 2: Add TV account behavior**

Import the TV Xiaohongshu account service and route path into `settings_controller.dart`, then add:

```dart
void xiaohongshuTap() async {
  if (!XiaohongshuAccountService.instance.hasCookie.value) {
    Get.toNamed(RoutePath.kXiaohongshuQRLogin);
    return;
  }
  final action = await Utils.showOptionDialog<String>(
    ['扫码重新登录', '清除 Cookie'],
    '扫码重新登录',
    title: '小红书账号',
  );
  if (action == '扫码重新登录') {
    Get.toNamed(RoutePath.kXiaohongshuQRLogin);
  } else if (action == '清除 Cookie') {
    XiaohongshuAccountService.instance.clearCookie();
    SmartDialog.showToast('已清除小红书 Cookie');
  }
}
```

- [ ] **Step 3: Add the TV Xiaohongshu settings tile**

Append an `Obx` tile after the Douyin tile:

```dart
Obx(
  () => HighlightListTile(
    focusNode: AppFocusNode(),
    title: '小红书账号',
    subtitle: XiaohongshuAccountService.instance.hasCookie.value
        ? '已登录，点击可重新登录或清除 Cookie'
        : '未登录，点击扫码登录',
    leading: Image.asset(
      'assets/images/logo.png',
      width: 64.w,
      height: 64.w,
    ),
    onTap: controller.xiaohongshuTap,
  ),
),
```

Ensure an `AppStyle.vGap24` separates it from the previous tile.

- [ ] **Step 4: Format, analyze, and commit the TV integration**

Run:

```bash
dart format simple_live_tv_app/lib/routes/route_path.dart \
  simple_live_tv_app/lib/routes/app_pages.dart \
  simple_live_tv_app/lib/modules/settings/settings_controller.dart \
  simple_live_tv_app/lib/modules/settings/settings_page.dart
cd simple_live_tv_app
flutter analyze lib/routes lib/modules/settings
```

Expected: analysis reports no issues introduced by the TV route or tile.

```bash
git add simple_live_tv_app/lib/routes/route_path.dart \
  simple_live_tv_app/lib/routes/app_pages.dart \
  simple_live_tv_app/lib/modules/settings/settings_controller.dart \
  simple_live_tv_app/lib/modules/settings/settings_page.dart
git commit -m "Wire TV Xiaohongshu QR login"
```

### Task 6: Full Verification and Local Feature Commit

**Files:**
- Verify: all files from Tasks 1-5.
- Include after verification: existing modified Xiaohongshu files in `simple_live_app`, `simple_live_core`, and `simple_live_tv_app`.
- Exclude: `.vscode/settings.json`, `third_party/canvas_danmaku/.dart_tool/`, `third_party/canvas_danmaku/pubspec.lock`, and `tools/sync_apks_to_smb.sh`.

**Interfaces:**
- Consumes: the complete QR login flow and the user's existing Xiaohongshu changes.
- Produces: a clean, verified local feature commit without unrelated workspace content.

- [ ] **Step 1: Format every changed Dart file**

Run `dart format` with the explicit changed-file list printed by `git diff --name-only -- '*.dart'`, excluding every unrelated path before execution. Do not format whole package directories.

Expected: formatter completes successfully and changes only the QR-login files plus the four pre-existing Xiaohongshu Dart files included by this feature.

- [ ] **Step 2: Run focused and existing Xiaohongshu tests**

Run:

```bash
cd simple_live_core
dart test test/xiaohongshu_cookie_helper_test.dart test/xiaohongshu_site_test.dart
cd ../simple_live_app
flutter test test/modules/mine/account/xiaohongshu/qr_login_controller_test.dart
cd ../simple_live_tv_app
flutter test test/modules/account/xiaohongshu/qr_login_controller_test.dart
```

Expected: all commands pass.

- [ ] **Step 3: Run package analysis**

Run:

```bash
cd simple_live_core && dart analyze
cd ../simple_live_app && flutter analyze
cd ../simple_live_tv_app && flutter analyze
```

Expected: no new errors. Record any pre-existing warnings separately and verify none point to changed lines.

- [ ] **Step 4: Review the exact commit scope**

Run:

```bash
git status --short
git diff --check
git diff --name-only
```

Expected: QR-login files plus the existing Xiaohongshu source/test changes are visible; unrelated editor, generated dependency, and tool files remain unstaged.

- [ ] **Step 5: Commit remaining verified local Xiaohongshu content**

Stage only explicit Xiaohongshu and QR-login paths. Do not use `git add .`.

```bash
git add simple_live_app/lib/services/xiaohongshu_account_service.dart \
  simple_live_core/lib/src/xiaohongshu_site.dart \
  simple_live_core/test/xiaohongshu_site_test.dart \
  simple_live_tv_app/lib/services/xiaohongshu_account_service.dart
git diff --cached --check
git commit -m "Complete Xiaohongshu local changes"
```

Expected: commit succeeds; unrelated working-tree files remain untracked or unstaged.
