import 'dart:convert';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:test/test.dart';

void main() {
  group('XiaohongshuSite parser helpers', () {
    final fixture =
        json.decode('''
{
  "room": {
    "id": "room-123",
    "title": "测试直播",
    "status": true,
    "online": 1234,
    "cover": "https://example.com/cover.jpg",
    "url": "https://www.xiaohongshu.com/livestream/room-123",
    "anchor": {
      "name": "测试主播",
      "avatar": "https://example.com/avatar.jpg"
    },
    "streams": [
      {
        "quality": "原画",
        "urls": [
          "https://example.com/live/origin.flv",
          "https://example.com/live/origin.m3u8"
        ]
      },
      {
        "quality": "高清",
        "urls": [
          "https://example.com/live/hd.flv"
        ]
      }
    ]
  }
}
''')
            as Map<String, dynamic>;

    test('builds room detail from fixture data', () {
      final detail = XiaohongshuSite.parseRoomDetailForTest(fixture);

      expect(detail.roomId, 'room-123');
      expect(detail.title, '测试直播');
      expect(detail.userName, '测试主播');
      expect(detail.userAvatar, 'https://example.com/avatar.jpg');
      expect(detail.cover, 'https://example.com/cover.jpg');
      expect(detail.online, 1234);
      expect(detail.status, isTrue);
      expect(detail.url, 'https://www.xiaohongshu.com/livestream/room-123');
    });

    test('builds play qualities from fixture data', () {
      final detail = XiaohongshuSite.parseRoomDetailForTest(fixture);
      final qualities = XiaohongshuSite.parsePlayQualitiesForTest(detail);

      expect(qualities.map((e) => e.quality), ['原画', '高清']);
    });

    test('parses pull_config stream urls from current_room_info', () {
      final detail = XiaohongshuSite.parseCurrentRoomInfo({
        'data': {
          'room_info': {
            'room_id': 570339312483994664,
            'title': '直播标题',
            'status': 1,
            'pull_config': json.encode({
              'streams': [
                {
                  'quality_type_name': '高清',
                  'master_url':
                      'http://live-source-play.xhscdn.com/live/room_hcv520e.flv',
                  'backup_urls': [
                    'http://live-source-play-bak-tx.xhscdn.com/live/room_hcv520e.flv',
                  ],
                },
              ],
            }),
          },
          'host_info': {
            'nickname': '主播',
            'avatar': 'https://example.com/avatar.jpg',
          },
        },
      }, fallbackRoomId: '570339312483994664');
      final qualities = XiaohongshuSite.parsePlayQualitiesForTest(detail);
      final url = XiaohongshuSite().getPlayUrls(
        detail: detail,
        quality: qualities.single,
      );

      expect(detail.roomId, '570339312483994664');
      expect(detail.status, isTrue);
      expect(qualities.single.quality, '高清');
      expect(
        url.then((value) => value.urls),
        completion([
          'https://live-source-play.xhscdn.com/live/room_hcv520e.flv',
          'https://live-source-play-bak-tx.xhscdn.com/live/room_hcv520e.flv',
        ]),
      );
    });

    test('resolves room id from livestream url', () {
      expect(
        XiaohongshuSite.resolveRoomId(
          'https://www.xiaohongshu.com/livestream/570339312483994664?source=web_live',
        ),
        '570339312483994664',
      );
      expect(
        XiaohongshuSite.resolveRoomId('570339312483994664'),
        '570339312483994664',
      );
    });

    test('parses squarefeed items into live room cards', () {
      final result = XiaohongshuSite.parseSquarefeedForTest({
        'data': {
          'feeds': [
            {
              'cursorScore': '170000',
              'live': {
                'trackId': 'track-1',
                'tRoomInfo': {
                  'roomId': 570339312483994664,
                  'roomIdStr': '570339312483994664',
                  'name': '发现页直播',
                  'title': '直播标题',
                  'displayCount': 32890,
                  'coverInfo': {'url': 'https://example.com/cover.jpg'},
                },
                'tLiveHostInfo': {
                  'nickname': '发现主播',
                  'avatar': 'https://example.com/avatar.jpg',
                },
              },
            },
          ],
        },
      });

      expect(result.items, hasLength(1));
      expect(result.items.single.roomId, '570339312483994664');
      expect(result.items.single.title, '发现页直播');
      expect(result.items.single.userName, '发现主播');
      expect(result.items.single.cover, 'https://example.com/cover.jpg');
      expect(result.items.single.online, 32890);
      expect(result.hasMore, isTrue);
    });

    test('parses snake_case squarefeed items', () {
      final result = XiaohongshuSite.parseSquarefeedForTest({
        'data': {
          'feeds': [
            {
              'cursor_score': '170000',
              'model_type': 'live',
              'type': 'live',
              'live': {
                'track_id': 'track-1',
                't_room_info': {
                  'room_id': 570339312483994664,
                  'room_id_str': '570339312483994664',
                  'room_title': '发现页直播',
                  'display_count': 32890,
                  'cover_info': {'url': 'https://example.com/cover.jpg'},
                },
                't_live_host_info': {
                  'nick_name': '发现主播',
                  'avatar': 'https://example.com/avatar.jpg',
                },
              },
            },
          ],
        },
      });

      expect(result.items, hasLength(1));
      expect(result.items.single.roomId, '570339312483994664');
      expect(result.items.single.title, '发现页直播');
      expect(result.items.single.userName, '发现主播');
    });

    test('falls back to recommend text and nested cover url', () {
      final result = XiaohongshuSite.parseSquarefeedForTest({
        'data': {
          'feeds': [
            {
              'recommend': {
                'live_rec_content_text': '推荐直播标题',
              },
              'live': {
                't_room_info': {
                  'room_id_str': '570339312483994664',
                  'cover_info': {
                    'url': 'https://example.com/nested-cover.jpg',
                  },
                },
                't_live_host_info': {
                  'nick_name': '推荐主播',
                },
              },
            },
          ],
        },
      });

      expect(result.items.single.title, '推荐直播标题');
      expect(result.items.single.cover, 'https://example.com/nested-cover.jpg');
      expect(result.items.single.userName, '推荐主播');
    });

    test('parses squarefeed items that only expose livestream links', () {
      final result = XiaohongshuSite.parseSquarefeedForTest({
        'success': true,
        'code': 0,
        'data': {
          'feeds': [
            {
              'live': {
                'room_info': {
                  'room_title': '链接型直播间',
                  'room_cover': 'https://example.com/cover-link.jpg',
                  'link':
                      'https://www.xiaohongshu.com/livestream/570345118965921935',
                },
                'host_info': {
                  'nick_name': '链接主播',
                },
              },
            },
          ],
        },
      });

      expect(result.items, hasLength(1));
      expect(result.items.single.roomId, '570345118965921935');
      expect(result.items.single.title, '链接型直播间');
      expect(result.items.single.userName, '链接主播');
      expect(result.items.single.cover, 'https://example.com/cover-link.jpg');
    });
    test('prefers h264 stream urls over orig for playback', () {
      final detail = XiaohongshuSite.parseCurrentRoomInfo({
        'data': {
          'room_info': {
            'room_id': '570346714529460690',
            'status': 1,
            'pull_config': json.encode({
              'streams': [
                {
                  'quality_type_name': '原画',
                  'master_url':
                      'https://live-source-play.xhscdn.com/live/570346714529460690_orig.flv',
                },
                {
                  'quality_type_name': '超清',
                  'master_url':
                      'https://live-source-play.xhscdn.com/live/570346714529460690_hcv520e.flv',
                },
              ],
            }),
          },
        },
      }, fallbackRoomId: '570346714529460690');
      final qualities = XiaohongshuSite.parsePlayQualitiesForTest(detail);
      final firstUrl = XiaohongshuSite()
          .getPlayUrls(detail: detail, quality: qualities.first);

      expect(qualities.first.quality, '超清');
      expect(
        firstUrl.then((value) => value.urls.first),
        completion(contains('hcv520e')),
      );
    });
  });
}
