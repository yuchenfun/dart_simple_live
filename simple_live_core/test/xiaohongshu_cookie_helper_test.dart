import 'package:simple_live_core/simple_live_core.dart';
import 'package:test/test.dart';

void main() {
  group('XiaohongshuCookieHelper', () {
    test('visitor cookies are not a login session', () {
      expect(
        XiaohongshuCookieHelper.isLoggedIn({'a1': 'visitor', 'webId': 'id'}),
        isFalse,
      );
    });

    test('a non-empty web_session is a login session', () {
      expect(
        XiaohongshuCookieHelper.isLoggedIn({'web_session': 'session-value'}),
        isTrue,
      );
      expect(
        XiaohongshuCookieHelper.isLoggedIn({'web_session': '  '}),
        isFalse,
      );
    });

    test('serialization is deterministic and skips invalid entries', () {
      expect(
        XiaohongshuCookieHelper.serialize({
          'web_session': 'abc==',
          '': 'ignored',
          'a1': 'visitor',
          'empty': '',
        }),
        'a1=visitor; web_session=abc==',
      );
    });
  });
}
