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
}
