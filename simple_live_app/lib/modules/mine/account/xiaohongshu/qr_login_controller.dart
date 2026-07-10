import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/services/xiaohongshu_account_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

enum XiaohongshuQRLoginStatus { loading, waiting, failed, completed }

typedef XiaohongshuCookieReader = Future<Map<String, String>> Function();
typedef XiaohongshuCookieSaver = void Function(String cookie);
typedef XiaohongshuLoginUiIsolator = Future<bool> Function();
typedef XiaohongshuSessionPreparer = Future<void> Function();

class XiaohongshuQRLoginController extends GetxController {
  XiaohongshuQRLoginController({
    XiaohongshuCookieReader? cookieReader,
    XiaohongshuCookieSaver? cookieSaver,
    XiaohongshuLoginUiIsolator? loginUiIsolator,
    XiaohongshuSessionPreparer? sessionPreparer,
    String? previousWebSession,
    int isolationMaxAttempts = 8,
    Duration isolationRetryDelay = const Duration(milliseconds: 250),
  })  : _cookieReader = cookieReader,
        _cookieSaver = cookieSaver,
        _loginUiIsolator = loginUiIsolator,
        _sessionPreparer = sessionPreparer,
        _previousWebSession = previousWebSession ??
            (cookieReader == null && cookieSaver == null
                ? _webSessionFromCookie(
                    XiaohongshuAccountService.instance.cookie,
                  )
                : null),
        _isolationMaxAttempts = isolationMaxAttempts,
        _isolationRetryDelay = isolationRetryDelay {
    _sessionReady = cookieReader != null && sessionPreparer == null;
  }

  static const loginUrl = 'https://www.xiaohongshu.com/';
  @visibleForTesting
  static const isolateLoginScript = r'''
(() => {
  const clickLogin = () => {
    const nodes = [...document.querySelectorAll('button, [role="button"]')];
    const login = nodes.find((node) => node.textContent.trim() === '登录');
    if (login) login.click();
  };
  clickLogin();
  const dialog = document.querySelector(
    '[role="dialog"], [class*="login"], [class*="Login"]'
  );
  const qr = dialog?.querySelector(
    'canvas, img[src*="qr"], [class*="qr"], [class*="Qr"], iframe'
  ) ?? document.querySelector(
    'iframe[src*="login"], iframe[src*="passport"]'
  );
  if (!qr) return false;
  const isIframe = qr.tagName?.toLowerCase() === 'iframe';
  let card = qr;
  if (!isIframe) {
    let node = qr.parentElement;
    while (node && node !== document.body) {
      const rect = node.getBoundingClientRect();
      const hasStatus = /扫码|二维码|登录/.test(node.textContent || '');
      if (hasStatus && rect.width > 0 && rect.height > 0 &&
          rect.width <= 720 && rect.height <= 760) {
        card = node;
        break;
      }
      if (node === dialog) break;
      node = node.parentElement;
    }
  }
  card.setAttribute('data-simple-live-login-card', 'true');
  qr.setAttribute('data-simple-live-login-qr', 'true');
  const oldStyle = document.getElementById('simple-live-login-isolation');
  if (oldStyle) oldStyle.remove();
  const style = document.createElement('style');
  style.id = 'simple-live-login-isolation';
  style.textContent = `
    body > * { visibility: hidden !important; }
    [data-simple-live-login-card="true"],
    [data-simple-live-login-card="true"] * { visibility: visible !important; }
    [data-simple-live-login-card="true"] { position: fixed !important;
      left: 50% !important; top: 50% !important; transform: translate(-50%, -50%) !important;
      width: min(90vw, 560px) !important; max-height: 90vh !important;
      overflow: auto !important; box-sizing: border-box !important; }
    [data-simple-live-login-qr="true"] { aspect-ratio: 1 / 1 !important;
      object-fit: contain !important; width: min(60vmin, 360px) !important;
      height: auto !important; max-width: 100% !important; margin: auto !important; }
    iframe[data-simple-live-login-qr="true"] { width: min(90vw, 560px) !important;
      height: min(90vh, 680px) !important; aspect-ratio: auto !important;
      object-fit: contain !important; border: 0 !important; }
  `;
  document.head.appendChild(style);
  return true;
})()
''';

  final XiaohongshuCookieReader? _cookieReader;
  final XiaohongshuCookieSaver? _cookieSaver;
  final XiaohongshuLoginUiIsolator? _loginUiIsolator;
  final XiaohongshuSessionPreparer? _sessionPreparer;
  final String? _previousWebSession;
  final int _isolationMaxAttempts;
  final Duration _isolationRetryDelay;
  final status = XiaohongshuQRLoginStatus.loading.obs;
  final errorMessage = ''.obs;

  Timer? _pollTimer;
  InAppWebViewController? webViewController;
  bool _completed = false;
  bool _closed = false;
  int _generation = 0;
  Future<void>? _checkInFlight;
  bool _sessionReady = false;

  Future<void> attachController(InAppWebViewController controller) async {
    webViewController = controller;
    await _startSession(controller, loadPage: true);
  }

  Future<void> handleLoadStop(
    InAppWebViewController controller,
    WebUri? url,
  ) async {
    _pollTimer?.cancel();
    _checkInFlight = null;
    final generation = ++_generation;
    if (_sessionReady) await _prepareLoginUi(controller, generation);
  }

  void handleLoadError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceError error,
  ) {
    if (request.isForMainFrame != true) return;
    _pollTimer?.cancel();
    _checkInFlight = null;
    _generation++;
    _fail(error.description);
  }

  Future<void> reload() async {
    _pollTimer?.cancel();
    _checkInFlight = null;
    _generation++;
    _completed = false;
    errorMessage.value = '';
    status.value = XiaohongshuQRLoginStatus.loading;
    final controller = webViewController;
    if (controller != null) await _startSession(controller, loadPage: true);
  }

  @visibleForTesting
  Future<void> checkLoginForTest() => _checkLogin();

  @visibleForTesting
  Future<void> prepareLoginUiForTest() {
    final generation = ++_generation;
    return _prepareLoginUi(null, generation);
  }

  @visibleForTesting
  Future<void> startSessionForTest() => _startSession(null, loadPage: false);

  Future<void> _startSession(
    InAppWebViewController? controller, {
    required bool loadPage,
  }) async {
    _pollTimer?.cancel();
    _checkInFlight = null;
    final generation = ++_generation;
    _completed = false;
    _sessionReady = false;
    errorMessage.value = '';
    status.value = XiaohongshuQRLoginStatus.loading;
    try {
      if (_sessionPreparer != null) {
        await _sessionPreparer!();
      } else {
        await _clearWebViewCookies();
      }
      if (!_isCurrent(generation)) return;
      _sessionReady = true;
      if (loadPage) {
        await controller!.loadUrl(
          urlRequest: URLRequest(url: WebUri(loginUrl)),
        );
      } else {
        await _prepareLoginUi(null, generation);
      }
    } catch (error) {
      if (_isCurrent(generation)) _fail('准备扫码登录失败：$error');
    }
  }

  static Future<void> _clearWebViewCookies() async {
    final manager = CookieManager.instance();
    for (final url in const [
      'https://www.xiaohongshu.com',
      'https://xiaohongshu.com',
      'https://live-room.xiaohongshu.com',
    ]) {
      await manager.deleteCookies(url: WebUri(url), domain: '.xiaohongshu.com');
      await manager.deleteCookies(url: WebUri(url));
    }
  }

  Future<void> _prepareLoginUi(
    InAppWebViewController? controller,
    int generation,
  ) async {
    for (var attempt = 0; attempt < _isolationMaxAttempts; attempt++) {
      if (!_isCurrent(generation)) return;
      try {
        final isolated = _loginUiIsolator != null
            ? await _loginUiIsolator!()
            : await controller!.evaluateJavascript(
                  source: isolateLoginScript,
                ) ==
                true;
        if (!_isCurrent(generation)) return;
        if (isolated) {
          errorMessage.value = '';
          status.value = XiaohongshuQRLoginStatus.waiting;
          _pollTimer = Timer.periodic(
            const Duration(seconds: 2),
            (_) => unawaited(_checkLogin()),
          );
          return;
        }
      } catch (error) {
        if (!_isCurrent(generation)) return;
        if (attempt == _isolationMaxAttempts - 1) {
          _fail('登录二维码加载失败：$error');
          return;
        }
      }
      if (attempt < _isolationMaxAttempts - 1) {
        await Future<void>.delayed(_isolationRetryDelay);
      }
    }
    if (_isCurrent(generation)) {
      _fail('未找到小红书登录二维码，请重新加载');
    }
  }

  Future<void> _checkLogin() {
    if (_completed || _closed || !_sessionReady) return Future<void>.value();
    final activeCheck = _checkInFlight;
    if (activeCheck != null) return activeCheck;
    final generation = _generation;
    late final Future<void> check;
    check = _performLoginCheck(generation).whenComplete(() {
      if (identical(_checkInFlight, check)) _checkInFlight = null;
    });
    _checkInFlight = check;
    return check;
  }

  Future<void> _performLoginCheck(int generation) async {
    try {
      final Map<String, String> cookies;
      if (_cookieReader != null) {
        cookies = await _cookieReader!();
      } else {
        cookies = {
          for (final item in await CookieManager.instance().getCookies(
            url: WebUri(loginUrl),
          ))
            item.name: item.value,
        };
      }
      if (!_isCurrent(generation) || _completed) return;
      if (!XiaohongshuCookieHelper.isLoggedIn(cookies)) return;
      if (cookies['web_session'] == _previousWebSession) return;
      _pollTimer?.cancel();
      final value = XiaohongshuCookieHelper.serialize(cookies);
      (_cookieSaver ?? XiaohongshuAccountService.instance.setCookie)(value);
      _completed = true;
      status.value = XiaohongshuQRLoginStatus.completed;
      if (_cookieSaver == null) {
        SmartDialog.showToast('小红书登录成功');
        Get.back(result: true);
      }
    } catch (error) {
      if (_isCurrent(generation) && !_completed) {
        _pollTimer?.cancel();
        _fail('读取登录状态失败：$error');
      }
    }
  }

  bool _isCurrent(int generation) =>
      !_closed && !_completed && generation == _generation;

  static String? _webSessionFromCookie(String cookie) {
    for (final item in cookie.split(';')) {
      final parts = item.trim().split('=');
      if (parts.firstOrNull == 'web_session' && parts.length > 1) {
        return parts.sublist(1).join('=');
      }
    }
    return null;
  }

  void _fail(String message) {
    errorMessage.value = message;
    status.value = XiaohongshuQRLoginStatus.failed;
  }

  @override
  void onClose() {
    _pollTimer?.cancel();
    _closed = true;
    _checkInFlight = null;
    _generation++;
    super.onClose();
  }
}
