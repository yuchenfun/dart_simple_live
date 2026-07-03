import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/log.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/services/local_storage_service.dart';

class XiaohongshuAccountService extends GetxService {
  static XiaohongshuAccountService get instance =>
      Get.find<XiaohongshuAccountService>();

  var cookie = "";
  var hasCookie = false.obs;
  HeadlessInAppWebView? _headlessWebView;
  InAppWebViewController? _webViewController;
  Completer<Map<String, dynamic>>? _pendingRoomInfo;
  String _pendingRoomId = "";
  String _pendingApiPath = "";
  bool _cookiesSynced = false;
  Future<void> _requestQueue = Future.value();

  @override
  void onInit() {
    cookie = LocalStorageService.instance.getValue(
      LocalStorageService.kXiaohongshuCookie,
      "",
    );
    hasCookie.value = cookie.isNotEmpty;
    setSite();
    super.onInit();
  }

  void setSite() {
    final site =
        Sites.allSites[Constant.kXiaohongshu]!.liveSite as XiaohongshuSite;
    site.cookie = cookie;
    site.jsonFetcher = _canUseHeadlessProxy ? fetchJson : null;
  }

  void setCookie(String cookie) {
    this.cookie = cookie;
    LocalStorageService.instance.setValue(
      LocalStorageService.kXiaohongshuCookie,
      cookie,
    );
    hasCookie.value = cookie.isNotEmpty;
    _cookiesSynced = false;
    setSite();
  }

  void clearCookie() {
    cookie = "";
    LocalStorageService.instance.setValue(
      LocalStorageService.kXiaohongshuCookie,
      "",
    );
    hasCookie.value = false;
    _cookiesSynced = false;
    unawaited(_clearManagedCookies());
    setSite();
  }

  Future<Map<String, dynamic>> fetchJson(
    Uri uri,
    Map<String, dynamic>? body,
  ) async {
    if (!_canUseHeadlessProxy) {
      throw UnsupportedError("当前平台暂不支持小红书 WebView 代理");
    }
    if (!_canProxyApi(uri)) {
      throw UnsupportedError("小红书暂不支持 WebView 代理该接口：${uri.path}");
    }
    final roomId = uri.queryParameters['room_id']?.trim() ?? '';
    if (_isRoomInfoApi(uri) && roomId.isEmpty) {
      throw ArgumentError("缺少小红书 room_id");
    }
    final queued = _requestQueue
        .catchError((_) {})
        .then((_) => _fetchJsonLocked(uri, roomId, _targetUrlFor(uri, roomId)));
    _requestQueue = queued.then<void>((_) {}).catchError((_) {});
    return queued;
  }

  Future<Map<String, dynamic>> _fetchJsonLocked(
    Uri uri,
    String roomId,
    String targetUrl,
  ) async {
    await _ensureHeadlessWebView();
    await _syncCookiesToManager();
    _pendingRoomId = roomId;
    _pendingApiPath = uri.path;
    _pendingRoomInfo = Completer<Map<String, dynamic>>();
    await _webViewController?.loadUrl(
      urlRequest: URLRequest(
        url: WebUri(targetUrl),
      ),
    );
    try {
      return await _pendingRoomInfo!.future.timeout(
        const Duration(seconds: 18),
      );
    } finally {
      _pendingRoomInfo = null;
      _pendingRoomId = "";
      _pendingApiPath = "";
    }
  }

  Future<void> _ensureHeadlessWebView() async {
    if (_headlessWebView != null &&
        (_headlessWebView?.isRunning() ?? false) &&
        _webViewController != null) {
      return;
    }
    _headlessWebView ??= HeadlessInAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri("https://www.xiaohongshu.com/"),
      ),
      initialUserScripts: UnmodifiableListView([
        UserScript(
          source: _fetchResponseBridgeScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]),
      initialSettings: InAppWebViewSettings(
        userAgent: XiaohongshuSite.userAgent,
        isInspectable: kDebugMode,
        useShouldInterceptAjaxRequest: true,
        interceptOnlyAsyncAjaxRequests: false,
        javaScriptCanOpenWindowsAutomatically: true,
        supportMultipleWindows: true,
      ),
      onWebViewCreated: (controller) {
        _webViewController = controller;
        controller.addJavaScriptHandler(
          handlerName: "simpleLiveXhsFetchResponse",
          callback: (args) {
            if (args.isNotEmpty) {
              _handleFetchResponse(args.first);
            }
          },
        );
      },
      onAjaxReadyStateChange: (controller, ajaxRequest) async {
        _handleAjaxRequest(ajaxRequest);
        return AjaxRequestAction.PROCEED;
      },
      onConsoleMessage: (controller, consoleMessage) {
        Log.d("[XiaohongshuWebView] ${consoleMessage.message}");
      },
    );
    try {
      await _headlessWebView?.run();
    } catch (e) {
      _headlessWebView = null;
      _webViewController = null;
      throw StateError("启动小红书 WebView 代理失败：$e");
    }
  }

  Future<void> _syncCookiesToManager() async {
    if (_cookiesSynced || cookie.trim().isEmpty) {
      return;
    }
    await _clearManagedCookies();
    final manager = CookieManager.instance();
    final cookieMap = _parseCookieMap(cookie);
    for (final entry in cookieMap.entries) {
      await manager.setCookie(
        url: WebUri("https://www.xiaohongshu.com"),
        name: entry.key,
        value: entry.value,
        domain: ".xiaohongshu.com",
      );
    }
    _cookiesSynced = true;
  }

  Future<void> _clearManagedCookies() async {
    final manager = CookieManager.instance();
    for (final url in const [
      "https://www.xiaohongshu.com",
      "https://xiaohongshu.com",
      "https://live-room.xiaohongshu.com",
    ]) {
      try {
        await manager.deleteCookies(
            url: WebUri(url), domain: ".xiaohongshu.com");
        await manager.deleteCookies(url: WebUri(url));
      } catch (e) {
        Log.e("清理小红书 WebView Cookie 失败：$e", StackTrace.current);
      }
    }
  }

  void _handleAjaxRequest(AjaxRequest ajaxRequest) {
    final pending = _pendingRoomInfo;
    if (pending == null || pending.isCompleted) {
      return;
    }
    if (ajaxRequest.readyState?.toValue() !=
        AjaxRequestReadyState.DONE.toValue()) {
      return;
    }
    final url = ajaxRequest.responseURL?.toString() ??
        ajaxRequest.url?.toString() ??
        "";
    if (!_matchesPendingApi(url)) {
      return;
    }
    if (_pendingRoomId.isNotEmpty && !url.contains(_pendingRoomId)) {
      return;
    }
    final responseText = ajaxRequest.responseText ??
        (ajaxRequest.response is String ? ajaxRequest.response as String : "");
    if (responseText.trim().isEmpty) {
      return;
    }
    try {
      final decoded = json.decode(responseText);
      if (decoded is Map<String, dynamic>) {
        pending.complete(decoded);
      } else if (decoded is Map) {
        pending.complete(Map<String, dynamic>.from(decoded));
      }
    } catch (e) {
      Log.e("解析小红书 current_room_info 失败：$e", StackTrace.current);
    }
  }

  void _handleFetchResponse(dynamic payload) {
    final pending = _pendingRoomInfo;
    if (pending == null || pending.isCompleted) {
      return;
    }
    if (payload is! Map) {
      return;
    }
    final url = payload["url"]?.toString() ?? "";
    if (!_matchesPendingApi(url)) {
      return;
    }
    if (_pendingRoomId.isNotEmpty && !url.contains(_pendingRoomId)) {
      return;
    }
    final responseText = payload["responseText"]?.toString() ?? "";
    if (responseText.trim().isEmpty) {
      return;
    }
    try {
      final decoded = json.decode(responseText);
      if (decoded is Map<String, dynamic>) {
        pending.complete(decoded);
      } else if (decoded is Map) {
        pending.complete(Map<String, dynamic>.from(decoded));
      }
    } catch (e) {
      Log.e("解析小红书 fetch 响应失败：$e", StackTrace.current);
    }
  }

  static const String _fetchResponseBridgeScript = '''
(function() {
  function shouldReport(url) {
    return url.indexOf('/api/sns/red/live/web/feed/v1/squarefeed') >= 0 ||
      url.indexOf('/api/sns/red/live/web/v1/room/current_room_info') >= 0;
  }
  function report(url, text) {
    try {
      window.flutter_inappwebview.callHandler('simpleLiveXhsFetchResponse', {
        url: url,
        responseText: text
      });
    } catch (_) {}
  }
  if (!window.__simpleLiveXhsFetchHooked && typeof window.fetch === 'function') {
    window.__simpleLiveXhsFetchHooked = true;
    var originalFetch = window.fetch;
    window.fetch = function(input, init) {
      return originalFetch.apply(this, arguments).then(function(response) {
        try {
          var inputUrl = '';
          if (typeof input === 'string') {
            inputUrl = input;
          } else if (input && input.url) {
            inputUrl = input.url;
          }
          var responseUrl = response && response.url ? response.url : inputUrl;
          if (shouldReport(responseUrl) && response && response.clone) {
            response.clone().text().then(function(text) {
              report(responseUrl, text);
            }).catch(function() {});
          }
        } catch (_) {}
        return response;
      });
    };
  }
  if (!window.__simpleLiveXhsXhrHooked && window.XMLHttpRequest) {
    window.__simpleLiveXhsXhrHooked = true;
    var originalOpen = XMLHttpRequest.prototype.open;
    var originalSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function(method, url) {
      this.__simpleLiveXhsUrl = url;
      return originalOpen.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function() {
      var xhr = this;
      xhr.addEventListener('load', function() {
        try {
          var url = xhr.responseURL || xhr.__simpleLiveXhsUrl || '';
          if (shouldReport(url) && xhr.responseText) {
            report(url, xhr.responseText);
          }
        } catch (_) {}
      });
      return originalSend.apply(this, arguments);
    };
  }
})();
''';

  Map<String, String> _parseCookieMap(String value) {
    final result = <String, String>{};
    for (final part in value.split(';')) {
      final item = part.trim();
      if (item.isEmpty) {
        continue;
      }
      final index = item.indexOf('=');
      if (index <= 0) {
        continue;
      }
      final name = item.substring(0, index).trim();
      final cookieValue = item.substring(index + 1).trim();
      if (name.isNotEmpty && cookieValue.isNotEmpty) {
        result[name] = cookieValue;
      }
    }
    return result;
  }

  bool get _canUseHeadlessProxy =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows;

  bool _canProxyApi(Uri uri) => _isRoomInfoApi(uri) || _isSquarefeedApi(uri);

  bool _isRoomInfoApi(Uri uri) =>
      uri.path.endsWith('/api/sns/red/live/web/v1/room/current_room_info');

  bool _isSquarefeedApi(Uri uri) =>
      uri.path.endsWith('/api/sns/red/live/web/feed/v1/squarefeed');

  bool _matchesPendingApi(String url) {
    if (_pendingApiPath.isEmpty || url.isEmpty) {
      return false;
    }
    if (url.contains(_pendingApiPath)) {
      return true;
    }
    if (_isSquarefeedApi(Uri(path: _pendingApiPath))) {
      return url.contains('/feed/v1/squarefeed');
    }
    if (_isRoomInfoApi(Uri(path: _pendingApiPath))) {
      return url.contains('/room/current_room_info');
    }
    return false;
  }

  String _targetUrlFor(Uri uri, String roomId) {
    if (_isSquarefeedApi(uri)) {
      final cacheBuster = DateTime.now().millisecondsSinceEpoch;
      return '${XiaohongshuSite.liveListUrl}&_sl=$cacheBuster';
    }
    return "https://www.xiaohongshu.com/livestream/$roomId";
  }

  @override
  void onClose() {
    _headlessWebView?.dispose();
    _headlessWebView = null;
    _webViewController = null;
    super.onClose();
  }
}
