import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/services/xiaohongshu_account_service.dart';

enum XiaohongshuQRLoginStatus { loading, waiting, failed, completed }

typedef XiaohongshuCookieReader = Future<Map<String, String>> Function();
typedef XiaohongshuCookieSaver = void Function(String cookie);
typedef XiaohongshuLoginUiIsolator = Future<bool> Function();

class XiaohongshuQRLoginController extends GetxController {
  XiaohongshuQRLoginController({
    XiaohongshuCookieReader? cookieReader,
    XiaohongshuCookieSaver? cookieSaver,
    XiaohongshuLoginUiIsolator? loginUiIsolator,
    int isolationMaxAttempts = 8,
    Duration isolationRetryDelay = const Duration(milliseconds: 250),
  })  : _cookieReader = cookieReader,
        _cookieSaver = cookieSaver,
        _loginUiIsolator = loginUiIsolator,
        _isolationMaxAttempts = isolationMaxAttempts,
        _isolationRetryDelay = isolationRetryDelay;

  static const loginUrl = 'https://www.xiaohongshu.com/';
  static const _isolateLoginScript = r'''
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
  const target = dialog?.querySelector(
    'canvas, img[src*="qr"], [class*="qr"], [class*="Qr"], iframe'
  ) ?? document.querySelector(
    'iframe[src*="login"], iframe[src*="passport"]'
  );
  if (!target) return false;
  target.setAttribute('data-simple-live-login', 'true');
  const oldStyle = document.getElementById('simple-live-login-isolation');
  if (oldStyle) oldStyle.remove();
  const style = document.createElement('style');
  style.id = 'simple-live-login-isolation';
  style.textContent = `
    body > * { visibility: hidden !important; }
    [data-simple-live-login="true"],
    [data-simple-live-login="true"] * { visibility: visible !important; }
    [data-simple-live-login="true"] { position: fixed !important; inset: 0 !important;
      width: 100vw !important; height: 100vh !important; border: 0 !important; }
  `;
  document.head.appendChild(style);
  return true;
})()
''';

  final XiaohongshuCookieReader? _cookieReader;
  final XiaohongshuCookieSaver? _cookieSaver;
  final XiaohongshuLoginUiIsolator? _loginUiIsolator;
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

  void attachController(InAppWebViewController controller) {
    webViewController = controller;
  }

  Future<void> handleLoadStop(
    InAppWebViewController controller,
    WebUri? url,
  ) async {
    _pollTimer?.cancel();
    _checkInFlight = null;
    final generation = ++_generation;
    await _prepareLoginUi(controller, generation);
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
    await webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(loginUrl)),
    );
  }

  @visibleForTesting
  Future<void> checkLoginForTest() => _checkLogin();

  @visibleForTesting
  Future<void> prepareLoginUiForTest() {
    final generation = ++_generation;
    return _prepareLoginUi(null, generation);
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
                  source: _isolateLoginScript,
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
    if (_completed || _closed) return Future<void>.value();
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
