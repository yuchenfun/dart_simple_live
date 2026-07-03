import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/services/xiaohongshu_account_service.dart';

class XiaohongshuWebLoginController extends BaseController {
  static const _loginUrl = "https://www.xiaohongshu.com/";
  static const _userAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36";

  InAppWebViewController? webViewController;
  final CookieManager cookieManager = CookieManager.instance();
  final progress = 0.0.obs;
  final checking = false.obs;

  void onWebViewCreated(InAppWebViewController controller) {
    webViewController = controller;
    controller.loadUrl(urlRequest: URLRequest(url: WebUri(_loginUrl)));
  }

  void onProgressChanged(InAppWebViewController controller, int value) {
    progress.value = value / 100;
  }

  void onLoadStop(InAppWebViewController controller, Uri? uri) async {
    progress.value = 1;
    await saveCookie(silent: true);
  }

  Future<void> reload() async {
    await webViewController?.reload();
  }

  Future<void> saveCookie({bool silent = false}) async {
    if (checking.value) {
      return;
    }
    checking.value = true;
    try {
      final cookie = await _readCookie();
      if (cookie.isEmpty) {
        if (!silent) {
          SmartDialog.showToast("未读取到小红书 Cookie");
        }
        return;
      }
      if (!_hasLoginState(cookie)) {
        if (!silent) {
          SmartDialog.showToast("还没有检测到小红书登录态，请先在页面中完成登录");
        }
        return;
      }
      XiaohongshuAccountService.instance.setCookie(cookie);
      if (!silent) {
        SmartDialog.showToast("小红书登录态已保存");
        Get.back();
      }
    } catch (e) {
      Log.e("保存小红书 Cookie 失败：$e", StackTrace.current);
      if (!silent) {
        SmartDialog.showToast("保存失败：$e");
      }
    } finally {
      checking.value = false;
    }
  }

  Future<String> _readCookie() async {
    final values = <String, String>{};
    for (final url in const [
      "https://www.xiaohongshu.com",
      "https://xiaohongshu.com",
      "https://live-room.xiaohongshu.com",
    ]) {
      final cookies = await cookieManager.getCookies(url: WebUri(url));
      for (final item in cookies) {
        final name = item.name.trim();
        final value = item.value.trim();
        if (name.isNotEmpty && value.isNotEmpty) {
          values.putIfAbsent(name, () => value);
        }
      }
    }
    return values.entries.map((e) => "${e.key}=${e.value}").join("; ");
  }

  bool _hasLoginState(String cookie) {
    final lower = cookie.toLowerCase();
    return lower.contains("web_session=");
  }

  String get userAgent => _userAgent;
}
