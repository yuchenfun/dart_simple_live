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

class XiaohongshuQRLoginController extends GetxController {
  XiaohongshuQRLoginController({
    XiaohongshuCookieReader? cookieReader,
    XiaohongshuCookieSaver? cookieSaver,
  })  : _cookieReader = cookieReader,
        _cookieSaver = cookieSaver;

  static const loginUrl = 'https://www.xiaohongshu.com/';
  static const _isolateLoginScript = r'''
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
''';

  final XiaohongshuCookieReader? _cookieReader;
  final XiaohongshuCookieSaver? _cookieSaver;
  final status = XiaohongshuQRLoginStatus.loading.obs;
  final errorMessage = ''.obs;

  Timer? _pollTimer;
  InAppWebViewController? webViewController;
  bool _completed = false;

  void attachController(InAppWebViewController controller) {
    webViewController = controller;
  }

  Future<void> handleLoadStop(
    InAppWebViewController controller,
    WebUri? url,
  ) async {
    await controller.evaluateJavascript(source: _isolateLoginScript);
    if (_completed) return;
    errorMessage.value = '';
    status.value = XiaohongshuQRLoginStatus.waiting;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_checkLogin()),
    );
  }

  void handleLoadError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceError error,
  ) {
    if (request.isForMainFrame != true) return;
    _pollTimer?.cancel();
    errorMessage.value = error.description;
    status.value = XiaohongshuQRLoginStatus.failed;
  }

  Future<void> reload() async {
    _pollTimer?.cancel();
    _completed = false;
    errorMessage.value = '';
    status.value = XiaohongshuQRLoginStatus.loading;
    await webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(loginUrl)),
    );
  }

  @visibleForTesting
  Future<void> checkLoginForTest() => _checkLogin();

  Future<void> _checkLogin() async {
    if (_completed) return;
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
    if (!XiaohongshuCookieHelper.isLoggedIn(cookies)) return;
    _completed = true;
    _pollTimer?.cancel();
    final value = XiaohongshuCookieHelper.serialize(cookies);
    (_cookieSaver ?? XiaohongshuAccountService.instance.setCookie)(value);
    status.value = XiaohongshuQRLoginStatus.completed;
    if (_cookieSaver == null) {
      SmartDialog.showToast('小红书登录成功');
      Get.back(result: true);
    }
  }

  @override
  void onClose() {
    _pollTimer?.cancel();
    super.onClose();
  }
}
