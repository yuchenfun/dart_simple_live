import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/mine/account/xiaohongshu/qr_login_controller.dart';

void main() {
  test('completes login and saves serialized cookie', () async {
    String? savedCookie;
    final controller = XiaohongshuQRLoginController(
      cookieReader: () async => {'web_session': 'signed-in'},
      cookieSaver: (cookie) => savedCookie = cookie,
    );

    await controller.checkLoginForTest();

    expect(controller.status.value, XiaohongshuQRLoginStatus.completed);
    expect(savedCookie, 'web_session=signed-in');
  });

  test('concurrent checks read and save only once', () async {
    final readCompleter = Completer<Map<String, String>>();
    var reads = 0;
    var saves = 0;
    final controller = XiaohongshuQRLoginController(
      cookieReader: () {
        reads++;
        return readCompleter.future;
      },
      cookieSaver: (_) => saves++,
    );

    final first = controller.checkLoginForTest();
    final second = controller.checkLoginForTest();
    readCompleter.complete({'web_session': 'signed-in'});
    await Future.wait([first, second]);

    expect(reads, 1);
    expect(saves, 1);
  });

  test('reload invalidates an in-flight cookie read', () async {
    final readCompleter = Completer<Map<String, String>>();
    String? savedCookie;
    final controller = XiaohongshuQRLoginController(
      cookieReader: () => readCompleter.future,
      cookieSaver: (cookie) => savedCookie = cookie,
    );

    final check = controller.checkLoginForTest();
    await controller.reload();
    readCompleter.complete({'web_session': 'signed-in'});
    await check;

    expect(savedCookie, isNull);
    expect(controller.status.value, XiaohongshuQRLoginStatus.loading);
  });

  test('onClose invalidates an in-flight cookie read', () async {
    final readCompleter = Completer<Map<String, String>>();
    String? savedCookie;
    final controller = XiaohongshuQRLoginController(
      cookieReader: () => readCompleter.future,
      cookieSaver: (cookie) => savedCookie = cookie,
    );

    final check = controller.checkLoginForTest();
    controller.onClose();
    readCompleter.complete({'web_session': 'signed-in'});
    await check;

    expect(savedCookie, isNull);
  });

  test('fails safely when login DOM isolation times out', () async {
    var attempts = 0;
    final controller = XiaohongshuQRLoginController(
      cookieReader: () async => const {},
      cookieSaver: (_) {},
      loginUiIsolator: () async {
        attempts++;
        return false;
      },
      isolationMaxAttempts: 3,
      isolationRetryDelay: Duration.zero,
    );

    await controller.prepareLoginUiForTest();

    expect(attempts, 3);
    expect(controller.status.value, XiaohongshuQRLoginStatus.failed);
    expect(controller.errorMessage.value, isNotEmpty);
  });

  test('cookie read exceptions transition safely to failed', () async {
    final controller = XiaohongshuQRLoginController(
      cookieReader: () async => throw StateError('cookie failure'),
      cookieSaver: (_) {},
    );

    await controller.checkLoginForTest();

    expect(controller.status.value, XiaohongshuQRLoginStatus.failed);
    expect(controller.errorMessage.value, contains('cookie failure'));
  });
}
