import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/mine/account/xiaohongshu/qr_login_controller.dart';

void main() {
  test('isolation script selects card and preserves square QR', () async {
    final result = await _runIsolationFixture(hasQr: true);

    expect(result['result'], isTrue);
    expect(result['cardSelected'], isTrue);
    expect(result['qrSelected'], isTrue);
    expect(result['css'], contains('aspect-ratio: 1 / 1'));
    expect(result['css'], contains('object-fit: contain'));
    expect(result['css'], isNot(contains('width: 100vw')));
    expect(result['css'], isNot(contains('height: 100vh')));
  });

  test('isolation script fails closed when QR DOM is absent', () async {
    final result = await _runIsolationFixture(hasQr: false);

    expect(result['result'], isFalse);
    expect(result['styleAdded'], isFalse);
  });

  test('new session ignores old cookie until preparation and new login',
      () async {
    final prepared = Completer<void>();
    var cookies = {'web_session': 'old-session'};
    String? saved;
    final controller = XiaohongshuQRLoginController(
      cookieReader: () async => cookies,
      cookieSaver: (value) => saved = value,
      sessionPreparer: () => prepared.future,
      previousWebSession: 'old-session',
      loginUiIsolator: () async => true,
      isolationRetryDelay: Duration.zero,
    );

    final start = controller.startSessionForTest();
    await controller.checkLoginForTest();
    expect(saved, isNull);
    prepared.complete();
    await start;
    await controller.checkLoginForTest();
    expect(saved, isNull);
    cookies = {'web_session': 'new-session'};
    await controller.checkLoginForTest();
    expect(saved, 'web_session=new-session');
  });
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

Future<Map<String, dynamic>> _runIsolationFixture({required bool hasQr}) async {
  const script = XiaohongshuQRLoginController.isolateLoginScript;
  const fixture = r'''
class Element {
  constructor(name, text = '', rect = {width: 400, height: 500}) {
    this.name = name; this.textContent = text; this.rect = rect;
    this.parentElement = null; this.children = []; this.attrs = {}; this.style = {};
  }
  appendChild(child) { child.parentElement = this; this.children.push(child); return child; }
  setAttribute(key, value) { this.attrs[key] = value; }
  getBoundingClientRect() { return this.rect; }
  contains(node) { return node === this || this.children.some((c) => c.contains(node)); }
  querySelector(selector) {
    if (selector.includes('canvas') && globalThis.qr && this.contains(globalThis.qr)) return globalThis.qr;
    return null;
  }
  click() { this.clicked = true; }
  remove() { this.removed = true; }
}
const body = new Element('body');
const dialog = body.appendChild(new Element('dialog', '扫码登录 请使用小红书扫码', {width: 520, height: 620}));
const card = dialog.appendChild(new Element('card', '扫码登录 请使用小红书扫码', {width: 420, height: 520}));
globalThis.qr = HAS_QR ? card.appendChild(new Element('canvas', '', {width: 280, height: 280})) : null;
const login = new Element('button', '登录');
const head = new Element('head');
head.appendChild = (child) => { globalThis.addedStyle = child; return child; };
globalThis.document = {
  body, head,
  querySelector: (selector) => selector.includes('role="dialog"') ? dialog : null,
  querySelectorAll: () => [login],
  getElementById: () => null,
  createElement: () => new Element('style'),
};
const result = SCRIPT;
process.stdout.write(JSON.stringify({
  result,
  cardSelected: card.attrs['data-simple-live-login-card'] === 'true',
  qrSelected: qr?.attrs['data-simple-live-login-qr'] === 'true',
  styleAdded: !!globalThis.addedStyle,
  css: globalThis.addedStyle?.textContent || '',
}));
''';
  final source = fixture
      .replaceFirst('HAS_QR', hasQr ? 'true' : 'false')
      .replaceFirst('SCRIPT', script);
  final process = await Process.run('node', ['-e', source]);
  expect(process.exitCode, 0, reason: '${process.stderr}');
  return jsonDecode(process.stdout as String) as Map<String, dynamic>;
}
