import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_tv_app/modules/account/xiaohongshu/qr_login_controller.dart';

void main() {
  test('isolation script selects card and preserves square QR', () async {
    final result = await _runIsolationFixture(hasQr: true);
    expect(result['result'], isTrue);
    expect(result['cardSelected'], isTrue);
    expect(result['qrSelected'], isTrue);
    expect(result['css'], contains('aspect-ratio: 1 / 1'));
    expect(result['css'], contains('object-fit: contain'));
    expect(result['css'], isNot(contains('width: 100vw')));
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
    var saves = 0;
    final controller = XiaohongshuQRLoginController(
      cookieReader: () async => cookies,
      cookieSaver: (_) => saves++,
      sessionPreparer: () => prepared.future,
      previousWebSession: 'old-session',
      loginUiIsolator: () async => true,
      isolationRetryDelay: Duration.zero,
    );
    final start = controller.startSessionForTest();
    await controller.checkLoginForTest();
    expect(saves, 0);
    prepared.complete();
    await start;
    await controller.checkLoginForTest();
    expect(saves, 0);
    cookies = {'web_session': 'new-session'};
    await controller.checkLoginForTest();
    await controller.checkLoginForTest();
    expect(saves, 1);
  });
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
    await controller.checkLoginForTest();
    expect(reads, 1);
    expect(savedCookies, ['web_session=signed-in']);
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

Future<Map<String, dynamic>> _runIsolationFixture({required bool hasQr}) async {
  const script = XiaohongshuQRLoginController.isolateLoginScript;
  const fixture = r'''
class Element {
  constructor(name, text = '', rect = {width: 400, height: 500}) { this.name=name; this.textContent=text; this.rect=rect; this.parentElement=null; this.children=[]; this.attrs={}; }
  appendChild(child) { child.parentElement=this; this.children.push(child); return child; }
  setAttribute(key, value) { this.attrs[key]=value; }
  getBoundingClientRect() { return this.rect; }
  contains(node) { return node===this || this.children.some((c)=>c.contains(node)); }
  querySelector(selector) { return selector.includes('canvas') && globalThis.qr && this.contains(globalThis.qr) ? globalThis.qr : null; }
  click() {} remove() {}
}
const body=new Element('body'); const dialog=body.appendChild(new Element('dialog','扫码登录 请使用小红书扫码',{width:520,height:620}));
const card=dialog.appendChild(new Element('card','扫码登录 请使用小红书扫码',{width:420,height:520}));
globalThis.qr=HAS_QR ? card.appendChild(new Element('canvas','',{width:280,height:280})) : null;
const head=new Element('head'); head.appendChild=(child)=>{globalThis.addedStyle=child; return child;};
globalThis.document={body,head,querySelector:(s)=>s.includes('role="dialog"')?dialog:null,querySelectorAll:()=>[new Element('button','登录')],getElementById:()=>null,createElement:()=>new Element('style')};
const result=SCRIPT;
process.stdout.write(JSON.stringify({result,cardSelected:card.attrs['data-simple-live-login-card']==='true',qrSelected:qr?.attrs['data-simple-live-login-qr']==='true',styleAdded:!!globalThis.addedStyle,css:globalThis.addedStyle?.textContent||''}));
''';
  final source = fixture
      .replaceFirst('HAS_QR', hasQr ? 'true' : 'false')
      .replaceFirst('SCRIPT', script);
  final process = await Process.run('node', ['-e', source]);
  expect(process.exitCode, 0, reason: '${process.stderr}');
  return jsonDecode(process.stdout as String) as Map<String, dynamic>;
}
