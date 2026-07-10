import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_tv_app/modules/account/xiaohongshu/qr_login_controller.dart';

void main() {
  test('visitor cookies keep the controller waiting', () async {
    final controller = XiaohongshuQRLoginController(
      cookieReader: () async => {'a1': 'visitor'},
      cookieSaver: (_) {},
      loginUiIsolator: () async => true,
      isolationRetryDelay: Duration.zero,
    );

    await controller.prepareLoginUiForTest();
    expect(controller.status.value, XiaohongshuQRLoginStatus.waiting);

    await controller.checkLoginForTest();

    expect(controller.status.value, XiaohongshuQRLoginStatus.waiting);
    controller.onClose();
  });

  test('concurrent checks read and save a signed-in cookie only once',
      () async {
    final readCompleter = Completer<Map<String, String>>();
    final savedCookies = <String>[];
    var reads = 0;
    final controller = XiaohongshuQRLoginController(
      cookieReader: () {
        reads++;
        return readCompleter.future;
      },
      cookieSaver: savedCookies.add,
    );

    final first = controller.checkLoginForTest();
    final second = controller.checkLoginForTest();
    readCompleter.complete({'web_session': 'signed-in'});
    await Future.wait([first, second]);

    expect(reads, 1);
    expect(savedCookies, ['web_session=signed-in']);
    expect(controller.status.value, XiaohongshuQRLoginStatus.completed);
  });

  test('reload invalidates an in-flight cookie read', () async {
    final readCompleter = Completer<Map<String, String>>();
    final savedCookies = <String>[];
    final controller = XiaohongshuQRLoginController(
      cookieReader: () => readCompleter.future,
      cookieSaver: savedCookies.add,
    );

    final check = controller.checkLoginForTest();
    await controller.reload();
    readCompleter.complete({'web_session': 'signed-in'});
    await check;

    expect(savedCookies, isEmpty);
    expect(controller.status.value, XiaohongshuQRLoginStatus.loading);
  });

  test('onClose invalidates an in-flight cookie read', () async {
    final readCompleter = Completer<Map<String, String>>();
    final savedCookies = <String>[];
    final controller = XiaohongshuQRLoginController(
      cookieReader: () => readCompleter.future,
      cookieSaver: savedCookies.add,
    );

    final check = controller.checkLoginForTest();
    controller.onClose();
    readCompleter.complete({'web_session': 'signed-in'});
    await check;

    expect(savedCookies, isEmpty);
  });

  test('fails closed when login DOM isolation exhausts its attempts', () async {
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
