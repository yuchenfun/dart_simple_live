# Xiaohongshu Live Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Xiaohongshu live support to core, the main Flutter app, and the TV app with playback and Cookie-based account support, while keeping danmaku optional.

**Architecture:** Put all Xiaohongshu request and parsing behavior in `simple_live_core`, map web data to existing core models, and let both apps consume it through the existing `LiveSite` interface. The main app gets a WebView Cookie capture flow; the TV app gets manual Cookie management and account sync support. Danmaku is isolated behind a graceful no-op until stable transport details are found.

**Tech Stack:** Dart, Flutter, GetX, Hive, Dio, flutter_inappwebview, media_kit, existing `simple_live_core` live site interfaces.

---

## Reverse-Engineering Findings

Captured scratch artifacts live outside the repo in `/private/tmp/xiaohongshu-live-fixtures/`.

Observed on 2026-07-02:

- Live list route: `https://www.xiaohongshu.com/livelist?channel_id=&channel_type=web_live_tab`.
- Room route pattern: `https://www.xiaohongshu.com/livestream/{numeric_room_id}`.
- Example active room id: `570345118965921935`.
- Anonymous-style browser capture rendered the room and started playback.
- Candidate stream URL pattern: `https://live-source-play.xhscdn.com/live/{room_id}_*.flv?<signed-query>`.
- Candidate WebSocket: `wss://apppush-rws.xiaohongshu.com/rwp`. This is only a push/live-message candidate; danmaku semantics are not confirmed.
- Observed live API host: `live-room.xiaohongshu.com`.
- Observed live API paths:
  - `/api/sns/red/live/web/{room_id}/user_card`
  - `/api/sns/red/live/web/feed/category`
  - `/api/sns/red/live/web/feed/v1/squarefeed`
  - `/api/sns/red/live/web/v1/center/room/join/room`
  - `/api/sns/red/live/web/v1/room/aggregate_business_info`
  - `/api/sns/red/live/web/v1/room/current_room_info`
  - `/api/sns/red/live/web/v1/room/join_business_base_info`
  - `/api/sns/red/live/web/v1/room/join_comment_info`
- Query values, headers, cookies, response bodies, and signed playback query values were not saved. The implementation must discover the runtime playback URL through allowed HTTP responses or page/API parsing, not from committed secrets.

Implementation consequence:

- Direct room playback is plausible because the browser fetched a `.flv` resource successfully.
- Product code must still validate how to obtain the signed `.flv` URL from Xiaohongshu page/API data at runtime.
- Danmaku remains optional and should be reported as unavailable until WebSocket frames and message semantics are decoded.
- Discovery can start with `feed/category` and `feed/v1/squarefeed`, but direct room playback should land first.

Current blocker after Task 3 attempt:

- Shape-only capture succeeded for `current_room_info` and `{room_id}/user_card`.
- Those two response bodies provide room title, cover, live status, host nickname, avatar, and user-card metadata.
- They do not contain playback URL-like fields.
- The remaining observed live endpoints did not expose response bodies during bounded retry, so their request/body shapes remain unknown.
- The only confirmed playback evidence is the browser media request pattern `https://live-source-play.xhscdn.com/live/{room_id}_*.flv?<signed-query>`.
- Product implementation is blocked for actual playback until one of these is available:
  - a sanitized HAR/network export that includes response bodies for `join_business_base_info`, `join_comment_info`, `center/room/join/room`, or another endpoint that carries stream URLs;
  - a confirmed public JS/source-map analysis identifying the field path and request shape used to build the signed `.flv` URL;
  - an approved implementation approach that uses an embedded WebView/browser capture layer instead of pure Dart HTTP for Xiaohongshu playback.

---

## File Structure

Create:

- `simple_live_core/lib/src/xiaohongshu_site.dart`: Xiaohongshu `LiveSite` implementation, request headers, Cookie injection, parsing helpers, room/search/category/playback methods.
- `simple_live_core/lib/src/danmaku/xiaohongshu_danmaku.dart`: Xiaohongshu danmaku boundary with graceful unavailable behavior, and room argument type if stable danmaku details are found.
- `simple_live_core/test/xiaohongshu_site_test.dart`: Pure parser tests using fixed fixtures.
- `simple_live_app/lib/services/xiaohongshu_account_service.dart`: Main app Cookie storage, login state, and core site injection.
- `simple_live_app/lib/modules/mine/account/xiaohongshu/web_login_controller.dart`: Main app WebView Cookie capture logic.
- `simple_live_app/lib/modules/mine/account/xiaohongshu/web_login_page.dart`: Main app WebView login page.
- `simple_live_tv_app/lib/services/xiaohongshu_account_service.dart`: TV Cookie storage, login state, and core site injection.

Modify:

- `simple_live_core/lib/simple_live_core.dart`: Export Xiaohongshu site and danmaku classes.
- `simple_live_app/lib/app/constant.dart`: Add `Constant.kXiaohongshu`.
- `simple_live_app/lib/app/sites.dart`: Register Xiaohongshu.
- `simple_live_app/lib/app/controller/app_settings_controller.dart`: Ensure `initSiteSort()` appends missing sites and filters stale site ids.
- `simple_live_app/lib/services/local_storage_service.dart`: Add Xiaohongshu Cookie key.
- `simple_live_app/lib/main.dart`: Register `XiaohongshuAccountService`.
- `simple_live_app/lib/modules/mine/account/account_controller.dart`: Add Xiaohongshu account actions and WebView login entry.
- `simple_live_app/lib/modules/mine/account/account_page.dart`: Add Xiaohongshu account tile.
- `simple_live_app/lib/modules/mine/parse/parse_controller.dart`: Parse Xiaohongshu URLs and short links.
- `simple_live_app/lib/routes/route_path.dart`: Add Xiaohongshu WebView login route.
- `simple_live_app/lib/routes/app_pages.dart`: Register Xiaohongshu WebView login page.
- `simple_live_app/lib/services/profile_backup_service.dart`: Include Xiaohongshu Cookie import/export.
- `simple_live_app/lib/services/sync_service.dart`: Add local sync endpoint for Xiaohongshu Cookie.
- `simple_live_app/lib/requests/sync_client_request.dart`: Add client request for Xiaohongshu account sync.
- `simple_live_tv_app/lib/app/constant.dart`: Add `Constant.kXiaohongshu`.
- `simple_live_tv_app/lib/app/sites.dart`: Register Xiaohongshu with a new index.
- `simple_live_tv_app/lib/services/local_storage_service.dart`: Add Xiaohongshu Cookie key.
- `simple_live_tv_app/lib/main.dart`: Register `XiaohongshuAccountService`.
- `simple_live_tv_app/lib/modules/settings/settings_controller.dart`: Add Xiaohongshu Cookie actions.
- `simple_live_tv_app/lib/modules/settings/settings_page.dart`: Add Xiaohongshu account tile.
- `simple_live_tv_app/lib/services/profile_backup_service.dart`: Include Xiaohongshu Cookie import/export.
- `simple_live_tv_app/lib/services/sync_service.dart`: Add account sync endpoint.
- `simple_live_tv_app/lib/modules/sync/sync_controller.dart`: Add receiving/sending support if local sync exposes per-account controls.
- `simple_live_tv_app/lib/modules/sync/webdav/webdav_controller.dart`: Include Xiaohongshu Cookie in WebDAV account package.
- `simple_live_tv_app/lib/modules/sync/webdav/webdav_page.dart`: Add Xiaohongshu account sync toggle.
- `simple_live_app/pubspec.yaml` and `simple_live_tv_app/pubspec.yaml`: Ensure image assets cover the new logo if explicit asset paths are listed.

Asset:

- Add `simple_live_app/assets/images/xiaohongshu.png`.
- Add `simple_live_tv_app/assets/images/xiaohongshu.png`.

Use a simple red square icon with the text "小红书" only if no official project-compatible asset exists locally. Do not fetch copyrighted assets into the repository without confirming license suitability.

---

### Task 1: Capture Xiaohongshu Web Fixtures

**Files:**
- Create or update outside source tree during exploration: `/private/tmp/xiaohongshu-live-fixtures/`
- Later copy minimized fixture snippets into `simple_live_core/test/xiaohongshu_site_test.dart`

- [ ] **Step 1: Create a scratch fixture directory**

Run:

```bash
mkdir -p /private/tmp/xiaohongshu-live-fixtures
```

Expected: command exits with code 0.

- [ ] **Step 2: Find one active Xiaohongshu live room in a browser**

Use a normal browser or the app WebView during implementation. Save these observations in `/private/tmp/xiaohongshu-live-fixtures/notes.md`:

```markdown
# Xiaohongshu Live Fixture Notes

Room URL:
Canonical room id:
Anchor name:
Room title:
Cover URL:
Observed live status:
Observed stream URL keys:
Observed API endpoints:
Cookie required for room detail: yes/no
Cookie required for playback URL: yes/no
Danmaku WebSocket URL found: yes/no
```

Expected: at least `Room URL`, `Canonical room id`, and whether playback data appears in page HTML or API JSON are filled.

- [ ] **Step 3: Save minimized room data**

Create `/private/tmp/xiaohongshu-live-fixtures/room_detail_min.json` containing only fields needed for tests. Use this shape when raw fields differ:

```json
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
```

Expected: fixture has no personal Cookie, token, phone number, user id, or other sensitive fields.

- [ ] **Step 4: Commit nothing**

The scratch fixtures stay outside the repo. Only minimized, non-sensitive test data may be copied into test source in Task 2.

Expected: `git status --short` does not show `/private/tmp/xiaohongshu-live-fixtures`.

---

### Task 2: Add Core Parser Tests First

**Files:**
- Create: `simple_live_core/test/xiaohongshu_site_test.dart`
- Later modify: `simple_live_core/lib/src/xiaohongshu_site.dart`

- [ ] **Step 1: Write failing parser tests**

Create `simple_live_core/test/xiaohongshu_site_test.dart` with:

```dart
import 'dart:convert';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:test/test.dart';

void main() {
  group('XiaohongshuSite parser helpers', () {
    final fixture = json.decode('''
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
''') as Map<String, dynamic>;

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

    test('builds play urls for selected quality', () {
      final detail = XiaohongshuSite.parseRoomDetailForTest(fixture);
      final qualities = XiaohongshuSite.parsePlayQualitiesForTest(detail);
      final playUrl = XiaohongshuSite.parsePlayUrlsForTest(
        detail,
        qualities.first,
      );

      expect(playUrl.urls, contains('https://example.com/live/origin.flv'));
      expect(playUrl.urls, contains('https://example.com/live/origin.m3u8'));
    });

    test('detects offline room data', () {
      final offlineFixture = json.decode('''
{
  "room": {
    "id": "room-456",
    "title": "下播直播间",
    "status": false,
    "online": 0,
    "anchor": {"name": "测试主播"},
    "streams": []
  }
}
''') as Map<String, dynamic>;

      final detail = XiaohongshuSite.parseRoomDetailForTest(offlineFixture);
      final qualities = XiaohongshuSite.parsePlayQualitiesForTest(detail);

      expect(detail.status, isFalse);
      expect(qualities, isEmpty);
    });

    test('merges Cookie into headers only when present', () {
      expect(
        XiaohongshuSite.buildHeadersForTest('').containsKey('cookie'),
        isFalse,
      );
      expect(
        XiaohongshuSite.buildHeadersForTest('a1=test')['cookie'],
        'a1=test',
      );
    });
  });
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
cd simple_live_core && dart test test/xiaohongshu_site_test.dart
```

Expected: FAIL because `XiaohongshuSite` does not exist.

- [ ] **Step 3: Commit the failing test only if working with strict TDD checkpoints**

Run:

```bash
git add simple_live_core/test/xiaohongshu_site_test.dart
git commit -m "test: cover Xiaohongshu core parsing"
```

Expected: commit succeeds. If the team prefers only green commits, skip this commit and include the test in Task 3's commit.

---

### Task 3: Capture Sanitized Live API Response Shapes

**Files:**
- Create: `/private/tmp/xiaohongshu-live-fixtures/api_shapes.md`
- Create: `/private/tmp/xiaohongshu-live-fixtures/api_shapes_summary.json`

- [ ] **Step 1: Capture allowed response shapes**

Using browser network tooling, capture sanitized shape-only summaries for these observed endpoints:

```text
GET live-room.xiaohongshu.com/api/sns/red/live/web/v1/room/current_room_info
GET live-room.xiaohongshu.com/api/sns/red/live/web/v1/room/join_business_base_info
GET live-room.xiaohongshu.com/api/sns/red/live/web/v1/room/join_comment_info
GET live-room.xiaohongshu.com/api/sns/red/live/web/{room_id}/user_card
GET live-room.xiaohongshu.com/api/sns/red/live/web/feed/category
GET live-room.xiaohongshu.com/api/sns/red/live/web/feed/v1/squarefeed
POST live-room.xiaohongshu.com/api/sns/red/live/web/v1/center/room/join/room
```

Do not save raw response bodies. Save only:

```json
{
  "endpoint": "host + path",
  "method": "GET",
  "status": 200,
  "queryKeys": ["room_id"],
  "requestBodyKeys": [],
  "topLevelKeys": ["code", "data", "msg", "success"],
  "dataShape": {
    "fieldName": "string|number|boolean|array|object|null",
    "nestedObject": {
      "childField": "string"
    },
    "arrayField": [
      {
        "itemField": "string"
      }
    ]
  },
  "containsPlaybackUrlLikeField": true,
  "playbackUrlFieldPaths": ["data.stream.url"],
  "containsRoomTitleLikeField": true,
  "containsAnchorLikeField": true
}
```

For any field whose value looks like a URL with signed query values, save only the field path and URL host/path pattern, not the query string.

- [ ] **Step 2: Write `api_shapes.md`**

Create `/private/tmp/xiaohongshu-live-fixtures/api_shapes.md` with:

```markdown
# Xiaohongshu Live API Shapes

Captured: 2026-07-02
Mode: anonymous-style browser network capture

## Endpoint Summary

### current_room_info
- Method:
- Path:
- Required query keys:
- Top-level keys:
- Useful data paths:
- Playback URL-like paths:

### join_business_base_info
- Method:
- Path:
- Required query keys:
- Top-level keys:
- Useful data paths:
- Playback URL-like paths:

### join_comment_info
- Method:
- Path:
- Required query keys:
- Top-level keys:
- Useful data paths:
- WebSocket or push config paths:

### user_card
- Method:
- Path:
- Required path params:
- Top-level keys:
- Useful data paths:

### feed/category
- Method:
- Path:
- Top-level keys:
- Category list paths:

### squarefeed
- Method:
- Path:
- Query or body keys:
- Top-level keys:
- Room list paths:

### center/room/join/room
- Method:
- Path:
- Request body keys:
- Top-level keys:
- Useful result paths:

## Safety

- No cookies saved.
- No auth headers saved.
- No raw response bodies saved.
- No signed query values saved.
```

- [ ] **Step 3: Write `api_shapes_summary.json`**

Create `/private/tmp/xiaohongshu-live-fixtures/api_shapes_summary.json` using the shape-only JSON schema from Step 1. It must be valid JSON and must not contain raw Cookie values, auth headers, `xsec_token`, signed query strings, personal account identifiers, phone numbers, or raw response bodies.

- [ ] **Step 4: Validate sanitization**

Run:

```bash
python3 -m json.tool /private/tmp/xiaohongshu-live-fixtures/api_shapes_summary.json >/dev/null
rg -n "cookie|Cookie|authorization|xsec_token|web_session|a1=|phone|mobile|access_token|sign|signature" /private/tmp/xiaohongshu-live-fixtures/api_shapes.md /private/tmp/xiaohongshu-live-fixtures/api_shapes_summary.json
```

Expected: JSON validation exits 0. `rg` may match explanatory safety text, but it must not reveal actual secret values.

- [ ] **Step 5: Commit nothing**

Run:

```bash
git status --short
```

Expected: only pre-existing unrelated repo changes are present; Task 1c creates scratch files only.

---

### Task 4: Implement Core Xiaohongshu Models and Parsing

**Files:**
- Create: `simple_live_core/lib/src/xiaohongshu_site.dart`
- Create: `simple_live_core/lib/src/danmaku/xiaohongshu_danmaku.dart`
- Modify: `simple_live_core/lib/simple_live_core.dart`
- Test: `simple_live_core/test/xiaohongshu_site_test.dart`

- [ ] **Step 1: Add the danmaku boundary**

Create `simple_live_core/lib/src/danmaku/xiaohongshu_danmaku.dart`:

```dart
import 'package:simple_live_core/simple_live_core.dart';

class XiaohongshuDanmakuArgs {
  final String roomId;
  final String cookie;
  final List<String> websocketUrls;

  const XiaohongshuDanmakuArgs({
    required this.roomId,
    this.cookie = '',
    this.websocketUrls = const [],
  });
}

class XiaohongshuDanmaku extends LiveDanmaku {
  @override
  Future start(dynamic args) async {
    onClose?.call('小红书弹幕暂不可用');
  }

  @override
  Future stop() async {
    onMessage = null;
    onClose = null;
    onReady = null;
  }
}
```

- [ ] **Step 2: Add the core site implementation**

Create `simple_live_core/lib/src/xiaohongshu_site.dart`:

```dart
import 'dart:convert';

import 'package:simple_live_core/src/common/http_client.dart';
import 'package:simple_live_core/src/danmaku/xiaohongshu_danmaku.dart';
import 'package:simple_live_core/src/interface/live_danmaku.dart';
import 'package:simple_live_core/src/interface/live_site.dart';
import 'package:simple_live_core/src/model/live_anchor_item.dart';
import 'package:simple_live_core/src/model/live_category.dart';
import 'package:simple_live_core/src/model/live_category_result.dart';
import 'package:simple_live_core/src/model/live_play_quality.dart';
import 'package:simple_live_core/src/model/live_play_url.dart';
import 'package:simple_live_core/src/model/live_room_detail.dart';
import 'package:simple_live_core/src/model/live_room_item.dart';
import 'package:simple_live_core/src/model/live_search_result.dart';

class XiaohongshuRoomData {
  final List<Map<String, dynamic>> streams;

  const XiaohongshuRoomData({this.streams = const []});
}

class XiaohongshuSite extends LiveSite {
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  XiaohongshuSite() {
    id = 'xiaohongshu';
    name = '小红书直播';
  }

  String cookie = '';

  static Map<String, dynamic> buildHeadersForTest(String cookie) =>
      _buildHeaders(cookie);

  static LiveRoomDetail parseRoomDetailForTest(Map<String, dynamic> data) =>
      _parseRoomDetail(data);

  static List<LivePlayQuality> parsePlayQualitiesForTest(
    LiveRoomDetail detail,
  ) =>
      _parsePlayQualities(detail);

  static LivePlayUrl parsePlayUrlsForTest(
    LiveRoomDetail detail,
    LivePlayQuality quality,
  ) =>
      _parsePlayUrls(detail, quality);

  static Map<String, dynamic> _buildHeaders(String cookie) {
    final headers = <String, dynamic>{
      'User-Agent': userAgent,
      'accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8',
      'referer': 'https://www.xiaohongshu.com/',
    };
    final value = cookie.trim();
    if (value.isNotEmpty) {
      headers['cookie'] = value;
    }
    return headers;
  }

  Map<String, dynamic> get _headers => _buildHeaders(cookie);

  @override
  LiveDanmaku getDanmaku() => XiaohongshuDanmaku();

  @override
  Future<List<LiveCategory>> getCategores() async {
    return [
      LiveCategory(
        id: 'recommend',
        name: '推荐',
        children: [
          LiveSubCategory(
            id: 'recommend',
            name: '推荐',
            parentId: 'recommend',
          ),
        ],
      ),
    ];
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    return LiveCategoryResult(hasMore: false, items: <LiveRoomItem>[]);
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    return getRecommendRooms(page: page);
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword, {int page = 1}) {
    return Future.value(
      LiveSearchRoomResult(hasMore: false, items: <LiveRoomItem>[]),
    );
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword, {int page = 1}) {
    return Future.value(
      LiveSearchAnchorResult(hasMore: false, items: <LiveAnchorItem>[]),
    );
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    final page = await HttpClient.instance.getText(
      _roomUrl(roomId),
      header: _headers,
    );
    return _parseRoomDetail(_extractRoomData(page, roomId));
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({
    required LiveRoomDetail detail,
  }) async {
    return _parsePlayQualities(detail);
  }

  @override
  Future<LivePlayUrl> getPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return _parsePlayUrls(detail, quality);
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final detail = await getRoomDetail(roomId: roomId);
    return detail.status;
  }

  static String _roomUrl(String roomId) {
    if (roomId.startsWith('http://') || roomId.startsWith('https://')) {
      return roomId;
    }
    return 'https://www.xiaohongshu.com/livestream/$roomId';
  }

  static Map<String, dynamic> _extractRoomData(String page, String roomId) {
    for (final pattern in [
      RegExp(r'<script[^>]+id="__INITIAL_STATE__"[^>]*>(.*?)</script>',
          dotAll: true),
      RegExp(r'window\.__INITIAL_STATE__\s*=\s*({.*?})\s*</script>',
          dotAll: true),
    ]) {
      final match = pattern.firstMatch(page);
      if (match == null) {
        continue;
      }
      final raw = match.group(1)?.trim() ?? '';
      if (raw.isEmpty) {
        continue;
      }
      final decoded = json.decode(_decodeHtml(raw));
      if (decoded is Map<String, dynamic>) {
        return _normalizeRoomData(decoded, fallbackRoomId: roomId);
      }
    }
    return {
      'room': {
        'id': roomId,
        'title': '',
        'status': false,
        'online': 0,
        'streams': const [],
      },
    };
  }

  static String _decodeHtml(String value) {
    return value
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }

  static Map<String, dynamic> _normalizeRoomData(
    Map<String, dynamic> data, {
    required String fallbackRoomId,
  }) {
    final existingRoom = data['room'];
    if (existingRoom is Map<String, dynamic>) {
      return data;
    }
    final room = _findFirstRoomMap(data) ?? <String, dynamic>{};
    return {
      'room': {
        'id': _firstString(room, const [
              'id',
              'roomId',
              'room_id',
              'liveRoomId',
              'live_room_id',
            ]) ??
            fallbackRoomId,
        'title': _firstString(room, const [
              'title',
              'name',
              'caption',
              'desc',
              'description',
            ]) ??
            '',
        'status': _firstBool(room, const [
          'status',
          'live',
          'isLive',
          'is_living',
          'living',
        ]),
        'online': _firstInt(room, const [
          'online',
          'onlineCount',
          'online_count',
          'viewer',
          'viewerCount',
        ]),
        'cover': _firstString(room, const [
              'cover',
              'coverUrl',
              'cover_url',
              'image',
              'imageUrl',
            ]) ??
            '',
        'url': _firstString(room, const ['url', 'webUrl', 'shareUrl']) ??
            _roomUrl(fallbackRoomId),
        'anchor': {
          'name': _firstString(room, const [
                'userName',
                'nickname',
                'nickName',
                'anchorName',
                'name',
              ]) ??
              '',
          'avatar': _firstString(room, const [
                'avatar',
                'avatarUrl',
                'avatar_url',
                'headUrl',
              ]) ??
              '',
        },
        'streams': _findStreams(room),
      },
    };
  }

  static Map<String, dynamic>? _findFirstRoomMap(dynamic value, {int depth = 0}) {
    if (depth > 8) {
      return null;
    }
    if (value is List) {
      for (final item in value) {
        final resolved = _findFirstRoomMap(item, depth: depth + 1);
        if (resolved != null) {
          return resolved;
        }
      }
      return null;
    }
    if (value is! Map) {
      return null;
    }
    final map = Map<String, dynamic>.from(value);
    if (_firstString(map, const ['roomId', 'room_id', 'liveRoomId']) != null ||
        _findStreams(map).isNotEmpty) {
      return map;
    }
    for (final item in map.values) {
      final resolved = _findFirstRoomMap(item, depth: depth + 1);
      if (resolved != null) {
        return resolved;
      }
    }
    return null;
  }

  static LiveRoomDetail _parseRoomDetail(Map<String, dynamic> data) {
    final room = Map<String, dynamic>.from(data['room'] as Map? ?? const {});
    final anchor = Map<String, dynamic>.from(room['anchor'] as Map? ?? const {});
    final streams = _findStreams(room);
    return LiveRoomDetail(
      roomId: room['id']?.toString() ?? '',
      title: room['title']?.toString() ?? '',
      userName: anchor['name']?.toString() ?? '',
      userAvatar: anchor['avatar']?.toString() ?? '',
      cover: room['cover']?.toString() ?? '',
      online: _asInt(room['online']),
      status: _asBool(room['status']) && streams.isNotEmpty,
      url: room['url']?.toString() ?? '',
      danmakuData: XiaohongshuRoomData(streams: streams),
    );
  }

  static List<LivePlayQuality> _parsePlayQualities(LiveRoomDetail detail) {
    final data = detail.danmakuData;
    final streams =
        data is XiaohongshuRoomData ? data.streams : <Map<String, dynamic>>[];
    final qualities = <LivePlayQuality>[];
    for (var i = 0; i < streams.length; i++) {
      final stream = streams[i];
      final name = stream['quality']?.toString().trim();
      final urls = _extractUrls(stream['urls']);
      if (urls.isEmpty) {
        continue;
      }
      qualities.add(
        LivePlayQuality(
          quality: name?.isNotEmpty == true ? name! : '默认',
          data: i,
        ),
      );
    }
    return qualities;
  }

  static LivePlayUrl _parsePlayUrls(
    LiveRoomDetail detail,
    LivePlayQuality quality,
  ) {
    final data = detail.danmakuData;
    final streams =
        data is XiaohongshuRoomData ? data.streams : <Map<String, dynamic>>[];
    final index = quality.data is int ? quality.data as int : 0;
    if (index < 0 || index >= streams.length) {
      return LivePlayUrl(urls: const []);
    }
    return LivePlayUrl(urls: _extractUrls(streams[index]['urls']));
  }

  static List<Map<String, dynamic>> _findStreams(dynamic value, {int depth = 0}) {
    if (depth > 8) {
      return const [];
    }
    if (value is List) {
      final direct = <Map<String, dynamic>>[];
      for (final item in value) {
        if (item is Map &&
            (_extractUrls(item['urls']).isNotEmpty ||
                _extractUrls(item['url']).isNotEmpty ||
                _extractUrls(item['playUrl']).isNotEmpty ||
                _extractUrls(item['play_url']).isNotEmpty)) {
          direct.add(Map<String, dynamic>.from(item));
        }
      }
      if (direct.isNotEmpty) {
        return direct;
      }
      return value
          .expand((item) => _findStreams(item, depth: depth + 1))
          .toList();
    }
    if (value is! Map) {
      return const [];
    }
    for (final key in const [
      'streams',
      'stream',
      'playStreams',
      'play_streams',
      'playUrls',
      'play_urls',
    ]) {
      final streams = _findStreams(value[key], depth: depth + 1);
      if (streams.isNotEmpty) {
        return streams;
      }
    }
    final urls = <String>[
      ..._extractUrls(value['urls']),
      ..._extractUrls(value['url']),
      ..._extractUrls(value['playUrl']),
      ..._extractUrls(value['play_url']),
      ..._extractUrls(value['flvUrl']),
      ..._extractUrls(value['hlsUrl']),
    ].toSet().toList();
    if (urls.isNotEmpty) {
      return [
        {
          'quality': _firstString(
                Map<String, dynamic>.from(value),
                const ['quality', 'qualityName', 'name', 'desc'],
              ) ??
              '默认',
          'urls': urls,
        },
      ];
    }
    return value.values
        .expand((item) => _findStreams(item, depth: depth + 1))
        .toList();
  }

  static List<String> _extractUrls(dynamic value) {
    if (value is String) {
      final url = value.trim();
      if (url.startsWith('http://') || url.startsWith('https://')) {
        return [url];
      }
      return const [];
    }
    if (value is List) {
      return value.expand(_extractUrls).toSet().toList();
    }
    if (value is Map) {
      return value.values.expand(_extractUrls).toSet().toList();
    }
    return const [];
  }

  static String? _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static int _firstInt(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final parsed = _asInt(map[key]);
      if (parsed > 0) {
        return parsed;
      }
    }
    return 0;
  }

  static bool _firstBool(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (_asBool(map[key])) {
        return true;
      }
    }
    return false;
  }

  static int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static bool _asBool(dynamic value) {
    if (value == true || value == 1) {
      return true;
    }
    final text = value?.toString().toLowerCase();
    return text == 'true' || text == '1' || text == 'living' || text == 'live';
  }
}
```

- [ ] **Step 3: Export the new core files**

Modify `simple_live_core/lib/simple_live_core.dart`:

```dart
export 'src/xiaohongshu_site.dart';
export 'src/danmaku/xiaohongshu_danmaku.dart';
```

Place the site export near other site exports and the danmaku export near other danmaku exports.

- [ ] **Step 4: Run core parser tests**

Run:

```bash
cd simple_live_core && dart test test/xiaohongshu_site_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit core parser foundation**

Run:

```bash
git add simple_live_core/lib/simple_live_core.dart simple_live_core/lib/src/xiaohongshu_site.dart simple_live_core/lib/src/danmaku/xiaohongshu_danmaku.dart simple_live_core/test/xiaohongshu_site_test.dart
git commit -m "feat: add Xiaohongshu core parser foundation"
```

Expected: commit succeeds.

---

### Task 5: Wire Xiaohongshu Into the Main App

**Files:**
- Modify: `simple_live_app/lib/app/constant.dart`
- Modify: `simple_live_app/lib/app/sites.dart`
- Modify: `simple_live_app/lib/app/controller/app_settings_controller.dart`
- Modify: `simple_live_app/lib/services/local_storage_service.dart`
- Create: `simple_live_app/lib/services/xiaohongshu_account_service.dart`
- Modify: `simple_live_app/lib/main.dart`
- Asset: `simple_live_app/assets/images/xiaohongshu.png`

- [ ] **Step 1: Add app constant**

In `simple_live_app/lib/app/constant.dart`, add after `kKuaishou`:

```dart
  static const String kXiaohongshu = "xiaohongshu";
```

- [ ] **Step 2: Register the site**

In `simple_live_app/lib/app/sites.dart`, add to `allSites` after Kuaishou:

```dart
    Constant.kXiaohongshu: Site(
      id: Constant.kXiaohongshu,
      logo: "assets/images/xiaohongshu.png",
      name: "小红书直播",
      liveSite: XiaohongshuSite(),
    ),
```

- [ ] **Step 3: Harden site sort migration**

In `simple_live_app/lib/app/controller/app_settings_controller.dart`, replace the body of `initSiteSort()` with:

```dart
  void initSiteSort() {
    final keys = Sites.allSites.keys.toList();
    final saved = LocalStorageService.instance
        .getValue(
          LocalStorageService.kSiteSort,
          keys.join(","),
        )
        .split(",")
        .where((item) => item.toString().trim().isNotEmpty)
        .map((item) => item.toString().trim())
        .where((item) => keys.contains(item))
        .toList();
    for (final key in keys) {
      if (!saved.contains(key)) {
        saved.add(key);
      }
    }
    siteSort.value = saved;
  }
```

- [ ] **Step 4: Add local storage key**

In `simple_live_app/lib/services/local_storage_service.dart`, add near other account keys:

```dart
  static const String kXiaohongshuCookie = "XiaohongshuCookie";
```

- [ ] **Step 5: Create main app account service**

Create `simple_live_app/lib/services/xiaohongshu_account_service.dart`:

```dart
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class XiaohongshuAccountService extends GetxService {
  static XiaohongshuAccountService get instance =>
      Get.find<XiaohongshuAccountService>();

  final hasCookie = false.obs;
  var cookie = "";

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
    final site = Sites.allSites[Constant.kXiaohongshu]?.liveSite;
    if (site is XiaohongshuSite) {
      site.cookie = cookie;
    }
  }

  void setCookie(String value) {
    cookie = value.trim();
    LocalStorageService.instance.setValue(
      LocalStorageService.kXiaohongshuCookie,
      cookie,
    );
    hasCookie.value = cookie.isNotEmpty;
    setSite();
  }

  Future<void> clearCookie() async {
    cookie = "";
    LocalStorageService.instance.setValue(
      LocalStorageService.kXiaohongshuCookie,
      "",
    );
    hasCookie.value = false;
    setSite();
    if (Platform.isAndroid || Platform.isIOS) {
      await CookieManager.instance().deleteAllCookies();
    }
  }
}
```

- [ ] **Step 6: Register service at startup**

In `simple_live_app/lib/main.dart`, import:

```dart
import 'package:simple_live_app/services/xiaohongshu_account_service.dart';
```

In `initServices()`, after `KuaishouAccountService` registration, add:

```dart
  Get.put(XiaohongshuAccountService());
```

- [ ] **Step 7: Add logo asset**

Add `simple_live_app/assets/images/xiaohongshu.png`. Use a locally created temporary icon if there is no approved asset:

```text
red background, white text 小红书, 512x512 png
```

Expected: image renders in account and site lists.

- [ ] **Step 8: Run main app analyze**

Run:

```bash
cd simple_live_app && flutter analyze
```

Expected: no new errors from Xiaohongshu registration or service code.

- [ ] **Step 9: Commit main app registration**

Run:

```bash
git add simple_live_app/lib/app/constant.dart simple_live_app/lib/app/sites.dart simple_live_app/lib/app/controller/app_settings_controller.dart simple_live_app/lib/services/local_storage_service.dart simple_live_app/lib/services/xiaohongshu_account_service.dart simple_live_app/lib/main.dart simple_live_app/assets/images/xiaohongshu.png
git commit -m "feat: register Xiaohongshu in main app"
```

Expected: commit succeeds.

---

### Task 6: Add Main App Login, Account UI, and URL Parsing

**Files:**
- Create: `simple_live_app/lib/modules/mine/account/xiaohongshu/web_login_controller.dart`
- Create: `simple_live_app/lib/modules/mine/account/xiaohongshu/web_login_page.dart`
- Modify: `simple_live_app/lib/routes/route_path.dart`
- Modify: `simple_live_app/lib/routes/app_pages.dart`
- Modify: `simple_live_app/lib/modules/mine/account/account_controller.dart`
- Modify: `simple_live_app/lib/modules/mine/account/account_page.dart`
- Modify: `simple_live_app/lib/modules/mine/parse/parse_controller.dart`

- [ ] **Step 1: Add route path**

In `simple_live_app/lib/routes/route_path.dart`, add near other account login routes:

```dart
  /// 小红书 Web登录
  static const kXiaohongshuWebLogin =
      "/settings/account/xiaohongshu/web_login";
```

- [ ] **Step 2: Create WebView login controller**

Create `simple_live_app/lib/modules/mine/account/xiaohongshu/web_login_controller.dart`:

```dart
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/services/xiaohongshu_account_service.dart';

class XiaohongshuWebLoginController extends BaseController {
  InAppWebViewController? webViewController;
  final CookieManager cookieManager = CookieManager.instance();

  void onWebViewCreated(InAppWebViewController controller) {
    webViewController = controller;
    webViewController!.loadUrl(
      urlRequest: URLRequest(
        url: WebUri("https://www.xiaohongshu.com/"),
      ),
    );
  }

  Future<void> onLoadStop(InAppWebViewController controller, Uri? uri) async {
    if (uri == null) {
      return;
    }
    if (uri.host.endsWith("xiaohongshu.com")) {
      await captureCookie(closeOnSuccess: false);
    }
  }

  Future<bool> captureCookie({bool closeOnSuccess = true}) async {
    final cookies = await cookieManager.getCookies(
      url: WebUri("https://www.xiaohongshu.com"),
    );
    if (cookies.isEmpty) {
      SmartDialog.showToast("未读取到小红书 Cookie");
      return false;
    }
    final cookieStr = cookies.map((e) => "${e.name}=${e.value}").join(";");
    XiaohongshuAccountService.instance.setCookie(cookieStr);
    SmartDialog.showToast("小红书 Cookie 已保存");
    if (closeOnSuccess) {
      Get.back();
    }
    return true;
  }
}
```

- [ ] **Step 3: Create WebView login page**

Create `simple_live_app/lib/modules/mine/account/xiaohongshu/web_login_page.dart` following the existing Bilibili/Douyin page pattern:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/mine/account/xiaohongshu/web_login_controller.dart';

class XiaohongshuWebLoginPage
    extends GetView<XiaohongshuWebLoginController> {
  const XiaohongshuWebLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("小红书网页登录"),
        actions: [
          TextButton(
            onPressed: () => controller.captureCookie(),
            child: const Text("保存"),
          ),
        ],
      ),
      body: InAppWebView(
        onWebViewCreated: controller.onWebViewCreated,
        onLoadStop: controller.onLoadStop,
      ),
    );
  }
}
```

- [ ] **Step 4: Register route**

In `simple_live_app/lib/routes/app_pages.dart`, add imports:

```dart
import 'package:simple_live_app/modules/mine/account/xiaohongshu/web_login_controller.dart';
import 'package:simple_live_app/modules/mine/account/xiaohongshu/web_login_page.dart';
```

Add a `GetPage` near other account login routes:

```dart
    //小红书Web登录
    GetPage(
      name: RoutePath.kXiaohongshuWebLogin,
      page: () => const XiaohongshuWebLoginPage(),
      bindings: [
        BindingsBuilder.put(() => XiaohongshuWebLoginController()),
      ],
    ),
```

- [ ] **Step 5: Add account controller actions**

In `simple_live_app/lib/modules/mine/account/account_controller.dart`, import:

```dart
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/xiaohongshu_account_service.dart';
```

Add methods:

```dart
  String getXiaohongshuCookieSummaryText() {
    return XiaohongshuAccountService.instance.hasCookie.value
        ? "已配置 Cookie，可用于小红书直播解析"
        : "可网页登录或手动粘贴 Cookie";
  }

  void xiaohongshuWebLogin() {
    Get.toNamed(RoutePath.kXiaohongshuWebLogin);
  }

  void xiaohongshuTap() async {
    final hasCookie = XiaohongshuAccountService.instance.hasCookie.value;
    final action = await Utils.showOptionDialog<String>(
      [
        "网页登录",
        "编辑或导入 Cookie",
        if (hasCookie) "查看当前 Cookie",
        if (hasCookie) "导出到剪贴板",
        if (hasCookie) "清除 Cookie",
      ],
      "网页登录",
      title: "小红书账号",
    );
    switch (action) {
      case "网页登录":
        xiaohongshuWebLogin();
        break;
      case "编辑或导入 Cookie":
        await _editXiaohongshuCookie();
        break;
      case "查看当前 Cookie":
        await _showCurrentXiaohongshuCookie();
        break;
      case "导出到剪贴板":
        await _exportXiaohongshuCookieToClipboard();
        break;
      case "清除 Cookie":
        await XiaohongshuAccountService.instance.clearCookie();
        SmartDialog.showToast("小红书 Cookie 已清除");
        break;
    }
  }

  Future<void> _editXiaohongshuCookie() async {
    final value = await Utils.showEditTextDialog(
      XiaohongshuAccountService.instance.cookie,
      title: "小红书 Cookie",
      hintText: "粘贴 www.xiaohongshu.com 的 Cookie",
    );
    if (value == null) {
      return;
    }
    XiaohongshuAccountService.instance.setCookie(value);
    SmartDialog.showToast(value.trim().isEmpty ? "已清除" : "已保存");
  }

  Future<void> _showCurrentXiaohongshuCookie() async {
    await Utils.showAlertDialog(
      XiaohongshuAccountService.instance.cookie.isEmpty
          ? "未配置 Cookie"
          : XiaohongshuAccountService.instance.cookie,
      title: "当前小红书 Cookie",
    );
  }

  Future<void> _exportXiaohongshuCookieToClipboard() async {
    await Clipboard.setData(
      ClipboardData(text: XiaohongshuAccountService.instance.cookie),
    );
    SmartDialog.showToast("已复制小红书 Cookie");
  }
```

If `Clipboard`, `SmartDialog`, or `Utils` are already imported in this controller, reuse existing imports and do not duplicate them.

- [ ] **Step 6: Add account page tile**

In `simple_live_app/lib/modules/mine/account/account_page.dart`, import:

```dart
import 'package:simple_live_app/services/xiaohongshu_account_service.dart';
```

Add after Kuaishou tile:

```dart
          Obx(
            () => ListTile(
              leading: Image.asset(
                'assets/images/xiaohongshu.png',
                width: 36,
                height: 36,
              ),
              title: const Text("小红书直播"),
              subtitle: Text(controller.getXiaohongshuCookieSummaryText()),
              trailing: XiaohongshuAccountService.instance.hasCookie.value
                  ? const Icon(Icons.check_circle_outline)
                  : const Icon(Icons.chevron_right),
              onTap: controller.xiaohongshuTap,
            ),
          ),
```

- [ ] **Step 7: Parse Xiaohongshu URLs**

In `simple_live_app/lib/modules/mine/parse/parse_controller.dart`, add before the final `return []`:

```dart
    if (url.contains("xiaohongshu.com") || url.contains("xhslink.com")) {
      if (url.contains("xhslink.com")) {
        final regExp = RegExp(r"http.?://xhslink\.com/[\d\w/]+");
        final u = regExp.firstMatch(url)?.group(0) ?? "";
        final location = await getLocation(u);
        return await parse(location);
      }
      final uri = Uri.tryParse(url);
      final path = uri?.path ?? "";
      final regExp = RegExp(r"(?:livestream|live|room)/([\d\w_-]+)");
      id = regExp.firstMatch(path)?.group(1) ?? "";
      if (id.isEmpty) {
        id = uri?.queryParameters["roomId"] ??
            uri?.queryParameters["room_id"] ??
            "";
      }
      if (id.isNotEmpty) {
        return [id, Sites.allSites[Constant.kXiaohongshu]!];
      }
    }
```

- [ ] **Step 8: Run main app analyze**

Run:

```bash
cd simple_live_app && flutter analyze
```

Expected: no errors from new route, page, controller, account tile, or parse code.

- [ ] **Step 9: Commit main app account flow**

Run:

```bash
git add simple_live_app/lib/modules/mine/account/xiaohongshu simple_live_app/lib/routes/route_path.dart simple_live_app/lib/routes/app_pages.dart simple_live_app/lib/modules/mine/account/account_controller.dart simple_live_app/lib/modules/mine/account/account_page.dart simple_live_app/lib/modules/mine/parse/parse_controller.dart
git commit -m "feat: add Xiaohongshu account flow in main app"
```

Expected: commit succeeds.

---

### Task 7: Wire Xiaohongshu Into the TV App

**Files:**
- Modify: `simple_live_tv_app/lib/app/constant.dart`
- Modify: `simple_live_tv_app/lib/app/sites.dart`
- Modify: `simple_live_tv_app/lib/services/local_storage_service.dart`
- Create: `simple_live_tv_app/lib/services/xiaohongshu_account_service.dart`
- Modify: `simple_live_tv_app/lib/main.dart`
- Modify: `simple_live_tv_app/lib/modules/settings/settings_controller.dart`
- Modify: `simple_live_tv_app/lib/modules/settings/settings_page.dart`
- Asset: `simple_live_tv_app/assets/images/xiaohongshu.png`

- [ ] **Step 1: Add TV constant**

In `simple_live_tv_app/lib/app/constant.dart`, add:

```dart
  static const String kXiaohongshu = "xiaohongshu";
```

- [ ] **Step 2: Register TV site**

In `simple_live_tv_app/lib/app/sites.dart`, add after Kuaishou:

```dart
    Constant.kXiaohongshu: Site(
      id: Constant.kXiaohongshu,
      logo: "assets/images/xiaohongshu.png",
      name: "小红书直播",
      liveSite: XiaohongshuSite(),
      index: 5,
    ),
```

- [ ] **Step 3: Add TV storage key**

In `simple_live_tv_app/lib/services/local_storage_service.dart`, add near account keys:

```dart
  static const String kXiaohongshuCookie = "XiaohongshuCookie";
```

- [ ] **Step 4: Create TV account service**

Create `simple_live_tv_app/lib/services/xiaohongshu_account_service.dart`:

```dart
import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/services/local_storage_service.dart';

class XiaohongshuAccountService extends GetxService {
  static XiaohongshuAccountService get instance =>
      Get.find<XiaohongshuAccountService>();

  final hasCookie = false.obs;
  var cookie = "";

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
    final site = Sites.allSites[Constant.kXiaohongshu]?.liveSite;
    if (site is XiaohongshuSite) {
      site.cookie = cookie;
    }
  }

  void setCookie(String value) {
    cookie = value.trim();
    LocalStorageService.instance.setValue(
      LocalStorageService.kXiaohongshuCookie,
      cookie,
    );
    hasCookie.value = cookie.isNotEmpty;
    setSite();
  }

  void clearCookie() {
    setCookie("");
  }
}
```

- [ ] **Step 5: Register TV service**

In `simple_live_tv_app/lib/main.dart`, import:

```dart
import 'package:simple_live_tv_app/services/xiaohongshu_account_service.dart';
```

In `initServices()`, add after Douyin account service:

```dart
  Get.put(XiaohongshuAccountService());
```

- [ ] **Step 6: Add TV settings controller actions**

In `simple_live_tv_app/lib/modules/settings/settings_controller.dart`, import:

```dart
import 'package:flutter/services.dart';
import 'package:simple_live_tv_app/services/xiaohongshu_account_service.dart';
```

Add:

```dart
  void xiaohongshuTap() async {
    final hasCookie = XiaohongshuAccountService.instance.hasCookie.value;
    final action = await Utils.showOptionDialog<String>(
      [
        "编辑或导入 Cookie",
        if (hasCookie) "查看当前 Cookie",
        if (hasCookie) "导出到剪贴板",
        if (hasCookie) "清除 Cookie",
      ],
      "编辑或导入 Cookie",
      title: "小红书账号",
    );
    switch (action) {
      case "编辑或导入 Cookie":
        final value = await Utils.showEditTextDialog(
          XiaohongshuAccountService.instance.cookie,
          title: "小红书 Cookie",
          hintText: "粘贴 www.xiaohongshu.com 的 Cookie",
        );
        if (value != null) {
          XiaohongshuAccountService.instance.setCookie(value);
          SmartDialog.showToast(value.trim().isEmpty ? "已清除" : "已保存");
        }
        break;
      case "查看当前 Cookie":
        await Utils.showAlertDialog(
          XiaohongshuAccountService.instance.cookie.isEmpty
              ? "未配置 Cookie"
              : XiaohongshuAccountService.instance.cookie,
          title: "当前小红书 Cookie",
        );
        break;
      case "导出到剪贴板":
        await Clipboard.setData(
          ClipboardData(text: XiaohongshuAccountService.instance.cookie),
        );
        SmartDialog.showToast("已复制小红书 Cookie");
        break;
      case "清除 Cookie":
        XiaohongshuAccountService.instance.clearCookie();
        SmartDialog.showToast("小红书 Cookie 已清除");
        break;
    }
  }
```

- [ ] **Step 7: Add TV account settings tile**

In `simple_live_tv_app/lib/modules/settings/settings_page.dart`, import:

```dart
import 'package:simple_live_tv_app/services/xiaohongshu_account_service.dart';
```

Add after the Douyin tile:

```dart
        AppStyle.vGap24,
        Obx(
          () => HighlightListTile(
            focusNode: AppFocusNode(),
            title: "小红书账号",
            subtitle: XiaohongshuAccountService.instance.hasCookie.value
                ? "已配置 Cookie，可用于小红书直播解析"
                : "可手动粘贴，或从手机/电脑端同步小红书 Cookie",
            leading: Image.asset(
              "assets/images/xiaohongshu.png",
              width: 64.w,
              height: 64.w,
            ),
            onTap: controller.xiaohongshuTap,
          ),
        ),
```

- [ ] **Step 8: Add TV logo asset**

Add `simple_live_tv_app/assets/images/xiaohongshu.png` matching the main app icon.

- [ ] **Step 9: Run TV analyze**

Run:

```bash
cd simple_live_tv_app && flutter analyze
```

Expected: no errors from Xiaohongshu site registration, service, or settings UI.

- [ ] **Step 10: Commit TV app support**

Run:

```bash
git add simple_live_tv_app/lib/app/constant.dart simple_live_tv_app/lib/app/sites.dart simple_live_tv_app/lib/services/local_storage_service.dart simple_live_tv_app/lib/services/xiaohongshu_account_service.dart simple_live_tv_app/lib/main.dart simple_live_tv_app/lib/modules/settings/settings_controller.dart simple_live_tv_app/lib/modules/settings/settings_page.dart simple_live_tv_app/assets/images/xiaohongshu.png
git commit -m "feat: register Xiaohongshu in TV app"
```

Expected: commit succeeds.

---

### Task 8: Add Account Backup and Sync Support

**Files:**
- Modify: `simple_live_app/lib/services/profile_backup_service.dart`
- Modify: `simple_live_app/lib/services/sync_service.dart`
- Modify: `simple_live_app/lib/requests/sync_client_request.dart`
- Modify: `simple_live_tv_app/lib/services/profile_backup_service.dart`
- Modify: `simple_live_tv_app/lib/services/sync_service.dart`
- Modify: `simple_live_tv_app/lib/modules/sync/webdav/webdav_controller.dart`
- Modify: `simple_live_tv_app/lib/modules/sync/webdav/webdav_page.dart`

- [ ] **Step 1: Export Xiaohongshu account in main profile backup**

In `simple_live_app/lib/services/profile_backup_service.dart`, add to `_exportAccounts()["items"]`:

```dart
        {
          "siteId": Constant.kXiaohongshu,
          "cookie": LocalStorageService.instance.getValue(
            LocalStorageService.kXiaohongshuCookie,
            "",
          ),
        },
```

In account import switch, add:

```dart
        case Constant.kXiaohongshu:
          XiaohongshuAccountService.instance.setCookie(cookie);
          break;
```

Add import:

```dart
import 'package:simple_live_app/services/xiaohongshu_account_service.dart';
```

- [ ] **Step 2: Add main local sync endpoint**

In `simple_live_app/lib/services/sync_service.dart`, import:

```dart
import 'package:simple_live_app/services/xiaohongshu_account_service.dart';
```

Add route beside other account routes:

```dart
      ..post('/sync/account/xiaohongshu', _syncXiaohongshuAccountRequest)
```

Add method:

```dart
  Future<shelf.Response> _syncXiaohongshuAccountRequest(
      shelf.Request request) async {
    try {
      final body = await request.readAsString();
      Log.d('_syncXiaohongshuAccountRequest');
      final jsonBody = json.decode(body);
      if (jsonBody is! Map) {
        throw const FormatException("账号数据格式不是对象");
      }
      final cookie = jsonBody['cookie']?.toString() ?? "";
      if (cookie.isEmpty) {
        throw const FormatException("账号 Cookie 为空");
      }
      XiaohongshuAccountService.instance.setCookie(cookie);
      SmartDialog.showToast('已同步小红书账号');
      return toJsonResponse({
        'status': true,
        'message': 'success',
      });
    } catch (e) {
      return toJsonResponse({
        'status': false,
        'message': e.toString(),
      });
    }
  }
```

- [ ] **Step 3: Add main sync client request**

In `simple_live_app/lib/requests/sync_client_request.dart`, add:

```dart
  Future<bool> syncXiaohongshuAccount(SyncClinet client, String cookie) async {
    var url = "http://${client.address}:${client.port}/sync/account/xiaohongshu";
    var response = await HttpClient.instance.postJson(
      url,
      data: {"cookie": cookie},
    );
    return response["status"] == true;
  }
```

- [ ] **Step 4: Mirror profile backup support in TV app**

In `simple_live_tv_app/lib/services/profile_backup_service.dart`, import:

```dart
import 'package:simple_live_tv_app/services/xiaohongshu_account_service.dart';
```

Add Xiaohongshu to account export:

```dart
        {
          "siteId": Constant.kXiaohongshu,
          "cookie": LocalStorageService.instance.getValue(
            LocalStorageService.kXiaohongshuCookie,
            "",
          ),
        },
```

Add import switch case:

```dart
        case Constant.kXiaohongshu:
          XiaohongshuAccountService.instance.setCookie(cookie);
          break;
```

- [ ] **Step 5: Add TV local sync endpoint**

In `simple_live_tv_app/lib/services/sync_service.dart`, import:

```dart
import 'package:simple_live_tv_app/services/xiaohongshu_account_service.dart';
```

Add route:

```dart
        ..post('/sync/account/xiaohongshu', _syncXiaohongshuAccountRequest)
```

Add method equivalent to main app with TV imports:

```dart
  Future<shelf.Response> _syncXiaohongshuAccountRequest(
      shelf.Request request) async {
    try {
      final body = await request.readAsString();
      Log.d('_syncXiaohongshuAccountRequest');
      final jsonBody = json.decode(body);
      if (jsonBody is! Map) {
        throw const FormatException("账号数据格式不是对象");
      }
      final cookie = jsonBody['cookie']?.toString() ?? "";
      if (cookie.isEmpty) {
        throw const FormatException("账号 Cookie 为空");
      }
      XiaohongshuAccountService.instance.setCookie(cookie);
      SmartDialog.showToast('已同步小红书账号');
      return toJsonResponse({
        'status': true,
        'message': 'success',
      });
    } catch (e) {
      return toJsonResponse({
        'status': false,
        'message': e.toString(),
      });
    }
  }
```

- [ ] **Step 6: Add WebDAV package item in TV**

In `simple_live_tv_app/lib/modules/sync/webdav/webdav_controller.dart`, add:

```dart
  final isSyncXiaohongshuAccount = true.obs;
  final _userXiaohongshuAccountJsonName = 'SimpleLive_xiaohongshu_account.json';
```

Add export archive item:

```dart
    _addJsonFile(archive, _userXiaohongshuAccountJsonName, {
      'data': {'cookie': XiaohongshuAccountService.instance.cookie},
    });
```

Add import handling:

```dart
    } else if (file.name == _userXiaohongshuAccountJsonName &&
        isSyncXiaohongshuAccount.value) {
      final cookie = data["data"]?["cookie"]?.toString() ?? "";
      XiaohongshuAccountService.instance.setCookie(cookie);
```

Add toggle:

```dart
  void changeIsSyncXiaohongshuAccount() {
    isSyncXiaohongshuAccount.value = !isSyncXiaohongshuAccount.value;
  }
```

- [ ] **Step 7: Add TV WebDAV toggle UI**

In `simple_live_tv_app/lib/modules/sync/webdav/webdav_page.dart`, add an account toggle beside Bilibili/Douyin:

```dart
                          WebDavSyncSwitchTile(
                            title: "小红书账号",
                            icon: Icons.account_circle_outlined,
                            value: controller.isSyncXiaohongshuAccount,
                            onTap: controller.changeIsSyncXiaohongshuAccount,
                          ),
```

Use the exact switch tile widget name used by the surrounding file; if the local widget has a different class name, use that existing class and pass the same fields.

- [ ] **Step 8: Run analysis**

Run:

```bash
cd simple_live_app && flutter analyze
cd ../simple_live_tv_app && flutter analyze
```

Expected: both commands pass.

- [ ] **Step 9: Commit sync support**

Run:

```bash
git add simple_live_app/lib/services/profile_backup_service.dart simple_live_app/lib/services/sync_service.dart simple_live_app/lib/requests/sync_client_request.dart simple_live_tv_app/lib/services/profile_backup_service.dart simple_live_tv_app/lib/services/sync_service.dart simple_live_tv_app/lib/modules/sync/webdav/webdav_controller.dart simple_live_tv_app/lib/modules/sync/webdav/webdav_page.dart
git commit -m "feat: sync Xiaohongshu account cookies"
```

Expected: commit succeeds.

---

### Task 9: Add Observed Endpoint Parsers and Keep Unsafe Requests Stubbed

**Files:**
- Modify: `simple_live_core/lib/src/xiaohongshu_site.dart`
- Test: `simple_live_core/test/xiaohongshu_site_test.dart`

- [ ] **Step 1: Add fixture-based search mapping test**

Extend `simple_live_core/test/xiaohongshu_site_test.dart` with:

```dart
    test('maps room list fixture to live room items', () {
      final listFixture = json.decode('''
{
  "items": [
    {
      "roomId": "room-123",
      "title": "测试直播",
      "cover": "https://example.com/cover.jpg",
      "userName": "测试主播",
      "userAvatar": "https://example.com/avatar.jpg",
      "online": 1234,
      "status": true
    }
  ],
  "hasMore": true
}
''') as Map<String, dynamic>;

      final result = XiaohongshuSite.parseRoomListForTest(listFixture);

      expect(result.hasMore, isTrue);
      expect(result.items.single.roomId, 'room-123');
      expect(result.items.single.title, '测试直播');
      expect(result.items.single.userName, '测试主播');
      expect(result.items.single.cover, 'https://example.com/cover.jpg');
    });
```

- [ ] **Step 2: Add room list parser**

In `simple_live_core/lib/src/xiaohongshu_site.dart`, add:

```dart
  static LiveCategoryResult parseRoomListForTest(Map<String, dynamic> data) =>
      _parseRoomList(data);

  static LiveCategoryResult _parseRoomList(Map<String, dynamic> data) {
    final rawItems = data['items'];
    final items = <LiveRoomItem>[];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is! Map) {
          continue;
        }
        final item = Map<String, dynamic>.from(raw);
        items.add(
          LiveRoomItem(
            roomId: _firstString(item, const ['roomId', 'room_id', 'id']) ?? '',
            title: _firstString(item, const ['title', 'name', 'caption']) ?? '',
            cover: _firstString(item, const ['cover', 'coverUrl']) ?? '',
            userName:
                _firstString(item, const ['userName', 'nickname', 'anchorName']) ??
                    '',
            userAvatar: _firstString(item, const ['userAvatar', 'avatar']) ?? '',
            online: _firstInt(item, const ['online', 'onlineCount']),
            status: _firstBool(item, const ['status', 'live', 'isLive']),
          ),
        );
      }
    }
    return LiveCategoryResult(
      hasMore: _asBool(data['hasMore']),
      items: items.where((item) => item.roomId.isNotEmpty).toList(),
    );
  }
```

- [ ] **Step 3: Add constants for observed endpoint paths**

In `simple_live_core/lib/src/xiaohongshu_site.dart`, add endpoint builders near `_roomUrl`:

```dart
  static Uri _liveApiUri(String path, [Map<String, dynamic>? query]) {
    return Uri.https('live-room.xiaohongshu.com', path, query?.map(
      (key, value) => MapEntry(key, value.toString()),
    ));
  }

  static Uri _currentRoomInfoUri(String roomId) => _liveApiUri(
        '/api/sns/red/live/web/v1/room/current_room_info',
        {'room_id': roomId},
      );

  static Uri _joinBusinessBaseInfoUri(String roomId) => _liveApiUri(
        '/api/sns/red/live/web/v1/room/join_business_base_info',
        {'room_id': roomId},
      );

  static Uri _userCardUri(String roomId) => _liveApiUri(
        '/api/sns/red/live/web/$roomId/user_card',
      );

  static Uri _feedCategoryUri() => _liveApiUri(
        '/api/sns/red/live/web/feed/category',
      );

  static Uri _squareFeedUri({int page = 1}) => _liveApiUri(
        '/api/sns/red/live/web/feed/v1/squarefeed',
        {'page': page},
      );
```

If implementation proves the actual query parameter names differ, update these builders and tests in the same task using the sanitized response/request notes from Task 1c.

- [ ] **Step 4: Keep discovery methods safe until response shapes are known**

Keep `searchRooms`, `getRecommendRooms`, and `getCategoryRooms` returning empty results until a concrete endpoint has been captured and reviewed. This keeps the app usable through direct room URLs while avoiding brittle guessed calls.

```dart
  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword, {int page = 1}) {
    return Future.value(
      LiveSearchRoomResult(hasMore: false, items: <LiveRoomItem>[]),
    );
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) {
    return Future.value(
      LiveCategoryResult(hasMore: false, items: <LiveRoomItem>[]),
    );
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) {
    return getRecommendRooms(page: page);
  }
```

When sanitized response shapes for `feed/category` and `feed/v1/squarefeed` are captured, create a follow-up patch that names the exact endpoint, method, request body or query parameters, required headers, and fixture file. Do not add speculative endpoint code in this task.

- [ ] **Step 5: Run core tests**

Run:

```bash
cd simple_live_core && dart test test/xiaohongshu_site_test.dart
```

Expected: PASS.

- [ ] **Step 6: Manually smoke test one room**

Run a small console snippet from `simple_live_core` once a room URL exists:

```bash
dart run example/simple_live_core_example.dart
```

If the example does not accept Xiaohongshu, temporarily inspect through a debugger or a local throwaway script outside the repo. Do not commit throwaway scripts.

Expected: `getRoomDetail`, `getPlayQualites`, and `getPlayUrls` return a live room and at least one playable URL for an active room only after runtime playback URL extraction is implemented. If response shapes are still insufficient, record that the room route renders but direct API extraction remains blocked.

- [ ] **Step 7: Commit observed endpoint parser support**

Run:

```bash
git add simple_live_core/lib/src/xiaohongshu_site.dart simple_live_core/test/xiaohongshu_site_test.dart
git commit -m "feat: fetch Xiaohongshu live room data"
```

Expected: commit succeeds.

---

### Task 10: Final Verification

**Files:**
- All touched files

- [ ] **Step 1: Run core tests**

Run:

```bash
cd simple_live_core && dart test
```

Expected: all tests pass. If live network tests in existing suite fail due to upstream platform availability, rerun the Xiaohongshu and other affected local tests, then record the failing external test names in the final report.

- [ ] **Step 2: Run main app analysis**

Run:

```bash
cd simple_live_app && flutter analyze
```

Expected: no errors.

- [ ] **Step 3: Run TV app analysis**

Run:

```bash
cd simple_live_tv_app && flutter analyze
```

Expected: no errors.

- [ ] **Step 4: Run focused UI smoke checks**

Manual checks:

```text
Main app:
- Account page shows 小红书直播.
- Web login page opens www.xiaohongshu.com.
- Manual Cookie save changes the account subtitle to configured.
- Paste a Xiaohongshu live URL into parse flow and open room.
- Playback starts for an active room with at least one quality.

TV app:
- Settings account page shows 小红书账号.
- Manual Cookie save changes the subtitle to configured.
- Xiaohongshu appears in category/search site selectors.
- Opening a known active room starts playback.
```

Expected: all checks pass, except danmaku may show the explicit unavailable message.

- [ ] **Step 5: Commit verification fixes when files changed**

If verification required fixes:

```bash
git add path/to/changed_file.dart path/to/changed_test.dart
git commit -m "fix: stabilize Xiaohongshu live support"
```

Expected: commit succeeds after replacing the sample paths with the actual changed file paths. If no fixes were needed, do not create an empty commit.

---

## Self-Review

- Spec coverage: core site, main app, TV app, account Cookie management, sync/backup, URL parsing, error handling, testing, and optional danmaku each have tasks.
- Placeholder scan: endpoint-specific discovery is deliberately kept as an empty-result implementation until a concrete captured endpoint is available, so the plan contains no guessed endpoint names.
- Type consistency: `Constant.kXiaohongshu`, `XiaohongshuSite`, `XiaohongshuDanmaku`, and both `XiaohongshuAccountService` classes use the same names across tasks.
