import 'dart:convert';

import 'package:simple_live_core/src/common/http_client.dart';
import 'package:simple_live_core/src/danmaku/xiaohongshu_danmaku.dart';
import 'package:simple_live_core/src/interface/live_danmaku.dart';
import 'package:simple_live_core/src/interface/live_site.dart';
import 'package:simple_live_core/src/model/live_category.dart';
import 'package:simple_live_core/src/model/live_category_result.dart';
import 'package:simple_live_core/src/model/live_play_quality.dart';
import 'package:simple_live_core/src/model/live_play_url.dart';
import 'package:simple_live_core/src/model/live_room_detail.dart';
import 'package:simple_live_core/src/model/live_room_item.dart';

typedef XiaohongshuSignedHeadersProvider =
    Future<Map<String, String>> Function(Uri uri, Map<String, dynamic>? body);

typedef XiaohongshuJsonFetcher =
    Future<Map<String, dynamic>> Function(Uri uri, Map<String, dynamic>? body);

class XiaohongshuSite extends LiveSite {
  XiaohongshuSite({this.signedHeadersProvider, this.jsonFetcher}) {
    id = "xiaohongshu";
    name = "小红书直播";
  }

  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';
  static const String webHost = 'https://www.xiaohongshu.com';
  static const String liveApiHost = 'https://live-room.xiaohongshu.com';
  static const String liveListUrl =
      '$webHost/livelist?channel_id=&channel_type=web_live_tab';
  static const String worldCupCategoryId = 'worldcup26';

  XiaohongshuSignedHeadersProvider? signedHeadersProvider;
  XiaohongshuJsonFetcher? jsonFetcher;

  String cookie = '';
  String _recommendCursorScore = '0';

  @override
  LiveDanmaku getDanmaku() => XiaohongshuDanmaku();

  @override
  Future<List<LiveCategory>> getCategores() async {
    return [
      LiveCategory(
        id: 'recommend',
        name: '推荐',
        children: [
          LiveSubCategory(id: 'recommend', name: '推荐', parentId: 'recommend'),
        ],
      ),
      LiveCategory(
        id: worldCupCategoryId,
        name: '世界杯专题',
        children: [
          LiveSubCategory(
            id: worldCupCategoryId,
            name: '世界杯专题',
            parentId: worldCupCategoryId,
          ),
        ],
      ),
    ];
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    if (category.id == worldCupCategoryId ||
        category.parentId == worldCupCategoryId) {
      return _getWorldCupRooms(page: page);
    }
    return getRecommendRooms(page: page);
  }

  Future<LiveCategoryResult> _getWorldCupRooms({int page = 1}) async {
    if (page > 1) {
      return LiveCategoryResult(hasMore: false, items: const []);
    }

    final liveBarUri = Uri.parse('$webHost/api/sns/web/worldcup/live_bar');
    final liveBarRooms = await _tryGetWorldCupRooms(liveBarUri);
    if (liveBarRooms.isNotEmpty) {
      return LiveCategoryResult(hasMore: false, items: liveBarRooms);
    }

    final calendarUri = Uri.parse('$webHost/api/sns/web/worldcup/calendar_info')
        .replace(
          queryParameters: const <String, String>{
            'competition_id': '1',
            'season_id': '13776',
            'team_id1': '0',
            'team_id2': '0',
            'need_start_time_minute': 'false',
            'player_id': '',
            'need_live': 'true',
          },
        );
    final calendarRooms = await _tryGetWorldCupRooms(calendarUri);
    return LiveCategoryResult(hasMore: false, items: calendarRooms);
  }

  Future<List<LiveRoomItem>> _tryGetWorldCupRooms(Uri uri) async {
    try {
      final result = await _getJson(uri);
      return _parseWorldCupRooms(result);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    if (page <= 1) {
      _recommendCursorScore = '0';
    }
    final uri =
        Uri.parse(
          '$liveApiHost/api/sns/red/live/web/feed/v1/squarefeed',
        ).replace(
          queryParameters: <String, String>{
            'cursorScore': _recommendCursorScore,
            'source': '13',
            'category': '',
            'preSource': '',
            'size': '27',
            'extra_info': json.encode({
              'image_formats': ['jpg', 'webp', 'avif'],
            }),
          },
        );
    final result = await _getJson(uri);
    _ensureSquarefeedSuccess(result);
    final parsed = _parseSquarefeed(result);
    final nextCursor = _lastSquarefeedCursor(result);
    if (nextCursor.isNotEmpty) {
      _recommendCursorScore = nextCursor;
    }
    return parsed;
  }

  static LiveCategoryResult parseSquarefeedForTest(Map<String, dynamic> data) {
    return _parseSquarefeed(data);
  }

  static List<LiveRoomItem> parseWorldCupRoomsForTest(
    Map<String, dynamic> data,
  ) {
    return _parseWorldCupRooms(data);
  }

  static List<LiveRoomItem> _parseWorldCupRooms(Map data) {
    final items = <LiveRoomItem>[];
    final seenRoomIds = <String>{};
    _collectWorldCupRooms(data, items, seenRoomIds);
    return items;
  }

  static void _collectWorldCupRooms(
    dynamic source,
    List<LiveRoomItem> items,
    Set<String> seenRoomIds, {
    String inheritedTitle = '',
    String inheritedCover = '',
    String inheritedUserName = '',
    int depth = 0,
  }) {
    if (depth > 12) {
      return;
    }
    if (source is Map) {
      final map = Map<String, dynamic>.from(source);
      final title = _firstNonEmpty([
        _firstString(map, const [
          'title',
          'match_title',
          'matchTitle',
          'room_title',
          'roomTitle',
          'name',
          'desc',
          'subtitle',
        ]),
        inheritedTitle,
        '世界杯直播',
      ]);
      final cover = _firstNonEmpty([_firstMediaUrl(map), inheritedCover]);
      final userName = _firstNonEmpty([
        _firstString(map, const [
          'nickname',
          'nick_name',
          'user_name',
          'userName',
          'anchor_name',
          'anchorName',
          'host_name',
          'hostName',
        ]),
        _firstWorldCupNestedUserName(map),
        inheritedUserName,
      ]);

      final roomId = _resolveWorldCupRoomId(map);
      if (roomId.isNotEmpty && seenRoomIds.add(roomId)) {
        items.add(
          LiveRoomItem(
            roomId: roomId,
            title: title,
            cover: cover,
            userName: userName,
            online: _firstInt(map, const [
              'online',
              'online_count',
              'display_count',
              'view_num',
              'viewer_count',
            ]),
          ),
        );
      }

      for (final value in map.values) {
        _collectWorldCupRooms(
          value,
          items,
          seenRoomIds,
          inheritedTitle: title,
          inheritedCover: cover,
          inheritedUserName: userName,
          depth: depth + 1,
        );
      }
    } else if (source is Iterable) {
      for (final item in source) {
        _collectWorldCupRooms(
          item,
          items,
          seenRoomIds,
          inheritedTitle: inheritedTitle,
          inheritedCover: inheritedCover,
          inheritedUserName: inheritedUserName,
          depth: depth + 1,
        );
      }
    }
  }

  static String _resolveWorldCupRoomId(Map source) {
    final direct = _firstString(source, const [
      'room_id_str',
      'room_id',
      'live_room_id',
      'web_room_id',
    ]);
    if (_looksLikeRoomId(direct)) {
      return direct;
    }
    return _extractRoomIdFromDirectLinks(source);
  }

  static String _extractRoomIdFromDirectLinks(Map source) {
    for (final key in const [
      'link',
      'url',
      'deeplink',
      'deep_link',
      'jump_url',
      'live_url',
      'liveUrl',
      'room_link',
      'room_url',
      'web_url',
    ]) {
      final value = _firstString(source, [key]);
      final resolved = _extractRoomIdFromText(value);
      if (resolved.isNotEmpty) {
        return resolved;
      }
    }
    return '';
  }

  static String _extractRoomIdFromText(String value) {
    final text = value.trim();
    if (text.isEmpty) {
      return '';
    }
    final fromLivestream = resolveRoomId(text);
    if (fromLivestream.isNotEmpty && fromLivestream != text) {
      return fromLivestream;
    }
    final roomIdMatch = RegExp(
      r'''["']?room_id["']?\s*[:=]\s*["']?(\d{10,})''',
    ).firstMatch(text);
    if (roomIdMatch != null) {
      return roomIdMatch.group(1) ?? '';
    }
    return '';
  }

  static String _firstWorldCupNestedUserName(Map source) {
    for (final key in const [
      'anchor',
      'host',
      'host_info',
      'hostInfo',
      'user',
      'user_info',
      'userInfo',
      'author',
    ]) {
      final value = source[key];
      if (value is Map) {
        final name = _firstString(value, const [
          'nickname',
          'nick_name',
          'name',
          'user_name',
          'userName',
        ]);
        if (name.isNotEmpty) {
          return name;
        }
      }
    }
    return '';
  }

  static LiveCategoryResult _parseSquarefeed(Map data) {
    final feeds = _findFeedList(data);
    final items = <LiveRoomItem>[];
    for (final feed in feeds.whereType<Map>()) {
      final item = _parseSquarefeedItem(feed);
      if (item != null) {
        items.add(item);
      }
    }
    final hasMore =
        _asApiBool(data['hasMore']) ||
        _asApiBool(data['has_more']) ||
        _asApiBool(_findMapByKey(data, 'page_info')?['has_more']) ||
        items.isNotEmpty;
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  static LiveRoomItem? _parseSquarefeedItem(Map feed) {
    final live = _coerceMap(feed['live']);
    if (live == null) {
      return null;
    }
    final recommend = _coerceMap(feed['recommend']);
    final roomInfo =
        _coerceMap(live['t_room_info']) ??
        _coerceMap(live['tRoomInfo']) ??
        _coerceMap(live['room_info']) ??
        live;
    final hostInfo =
        _coerceMap(live['t_live_host_info']) ??
        _coerceMap(live['tLiveHostInfo']) ??
        _coerceMap(live['host_info']) ??
        _coerceMap(roomInfo['host_info']) ??
        const <String, dynamic>{};
    final roomExtra =
        _coerceMap(live['room_extra_info']) ?? const <String, dynamic>{};

    var roomId = _resolveFeedRoomId(feed, live, roomInfo);
    if (roomId.isEmpty) {
      roomId = _findRoomIdDeep(roomInfo);
    }
    if (roomId.isEmpty) {
      roomId = _findRoomIdDeep(live);
    }
    if (roomId.isEmpty) {
      return null;
    }

    final title = _firstNonEmpty([
      _firstString(roomInfo, const [
        'room_title',
        'room_name',
        'roomTitle',
        'roomName',
        'name',
        'title',
        'live_title',
        'liveTitle',
        'caption',
        'desc',
      ]),
      _firstString(roomExtra, const [
        'room_title',
        'room_name',
        'title',
        'name',
        'desc',
      ]),
      _firstString(recommend ?? const {}, const [
        'live_rec_content_text',
        'desc',
        'title',
        'name',
      ]),
    ], fallback: '小红书直播');

    final cover = _firstNonEmpty([
      _firstMediaUrl(roomInfo),
      _firstMediaUrl(roomExtra),
      _firstMediaUrl(live),
      _firstMediaUrl(recommend ?? const {}),
    ]);

    final userName = _firstNonEmpty([
      _firstString(hostInfo, const [
        'nick_name',
        'nickName',
        'nickname',
        'name',
        'user_name',
        'userName',
      ]),
      _firstString(roomInfo, const [
        'host_name',
        'anchor_name',
        'nick_name',
        'nickname',
      ]),
      _firstString(roomExtra, const [
        'host_name',
        'anchor_name',
        'nick_name',
        'nickname',
      ]),
    ]);

    final online = _firstInt(roomInfo, const [
      'display_count',
      'displayCount',
      'online',
      'online_count',
      'view_num',
      'member_count',
      'viewer_count',
    ]);
    final onlineFromExtra = _firstInt(roomExtra, const [
      'display_count',
      'online',
      'online_count',
      'view_num',
    ]);

    return LiveRoomItem(
      roomId: roomId,
      title: title,
      cover: cover,
      userName: userName,
      online: online > 0 ? online : onlineFromExtra,
    );
  }

  static Map<String, dynamic>? _coerceMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    if (value is String && value.trim().startsWith('{')) {
      try {
        final decoded = json.decode(value);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    return null;
  }

  static String _firstNonEmpty(List<String> values, {String fallback = ''}) {
    for (final value in values) {
      if (value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return fallback;
  }

  static String _firstMediaUrl(dynamic source, {int depth = 0}) {
    if (depth > 6) {
      return '';
    }
    if (source is Map) {
      for (final key in const [
        'url',
        'cover',
        'cover_url',
        'room_cover',
        'image',
        'thumb',
        'pic',
        'avatar',
      ]) {
        final resolved = _firstMediaUrl(source[key], depth: depth + 1);
        if (resolved.isNotEmpty) {
          return resolved;
        }
      }
      for (final key in const [
        'cover_info',
        'coverInfo',
        'cover_image',
        'room_cover_info',
        'url_list',
        'urls',
      ]) {
        final resolved = _firstMediaUrl(source[key], depth: depth + 1);
        if (resolved.isNotEmpty) {
          return resolved;
        }
      }
      for (final value in source.values) {
        final resolved = _firstMediaUrl(value, depth: depth + 1);
        if (resolved.isNotEmpty) {
          return resolved;
        }
      }
    } else if (source is List) {
      for (final item in source) {
        final resolved = _firstMediaUrl(item, depth: depth + 1);
        if (resolved.isNotEmpty) {
          return resolved;
        }
      }
    } else if (source is String) {
      final value = source.trim();
      if (value.startsWith('http://') || value.startsWith('https://')) {
        return value.replaceFirst('http://', 'https://');
      }
    }
    return '';
  }

  static String _findRoomIdDeep(dynamic source, {int depth = 0}) {
    if (depth > 10) {
      return '';
    }
    if (source is Map) {
      for (final key in const [
        'roomIdStr',
        'room_id_str',
        'roomId',
        'room_id',
        'web_room_id',
        'live_room_id',
        'liveRoomId',
        'webRoomId',
        'id',
      ]) {
        final value = source[key]?.toString().trim() ?? '';
        if (_looksLikeRoomId(value)) {
          return value;
        }
      }
      for (final value in source.values) {
        final resolved = _findRoomIdDeep(value, depth: depth + 1);
        if (resolved.isNotEmpty) {
          return resolved;
        }
      }
    } else if (source is List) {
      for (final item in source) {
        final resolved = _findRoomIdDeep(item, depth: depth + 1);
        if (resolved.isNotEmpty) {
          return resolved;
        }
      }
    } else if (source is String && source.contains('livestream/')) {
      return resolveRoomId(source);
    }
    return '';
  }

  static bool _looksLikeRoomId(String value) {
    return RegExp(r'^\d{10,}$').hasMatch(value);
  }

  static List _findFeedList(Map data) {
    for (final key in const ['feeds', 'items', 'list', 'room_list']) {
      final feeds = _findListByKey(data, key);
      if (feeds.isNotEmpty) {
        return feeds;
      }
    }
    return const [];
  }

  static String _resolveFeedRoomId(Map feed, Map live, Map roomInfo) {
    var direct = _firstString(roomInfo, const [
      'roomIdStr',
      'room_id_str',
      'roomId',
      'room_id',
      'id',
    ]);
    if (direct.isEmpty) {
      direct = _firstString(live, const [
        'roomIdStr',
        'room_id_str',
        'roomId',
        'room_id',
        'id',
      ]);
    }
    if (direct.isNotEmpty) {
      return direct;
    }
    for (final source in [feed, live, roomInfo]) {
      final resolved = _extractRoomIdFromMap(source);
      if (resolved.isNotEmpty) {
        return resolved;
      }
    }
    return '';
  }

  static String _extractRoomIdFromMap(Map source) {
    for (final key in const [
      'link',
      'url',
      'deeplink',
      'deep_link',
      'jump_url',
      'live_url',
      'liveUrl',
      'room_link',
      'room_url',
      'web_url',
    ]) {
      final resolved = resolveRoomId(_firstString(source, [key]));
      if (resolved.isNotEmpty && resolved != _firstString(source, [key])) {
        return resolved;
      }
    }
    for (final value in source.values) {
      if (value is String && value.contains('livestream/')) {
        final resolved = resolveRoomId(value);
        if (resolved.isNotEmpty) {
          return resolved;
        }
      }
      if (value is Map) {
        final resolved = _extractRoomIdFromMap(value);
        if (resolved.isNotEmpty) {
          return resolved;
        }
      }
    }
    return '';
  }

  static void _ensureSquarefeedSuccess(Map data) {
    if (data.isEmpty) {
      throw const FormatException('小红书发现页响应为空');
    }
    final success = data['success'];
    final code = data['code'];
    if (success == false || code == -1 || code == '-1') {
      final message = data['msg']?.toString().trim();
      throw FormatException(
        message?.isNotEmpty == true
            ? '小红书发现页请求失败：$message'
            : '小红书发现页请求失败，请先在账号页登录或配置 Cookie',
      );
    }
  }

  static bool _asApiBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    final text = value?.toString().toLowerCase() ?? '';
    return text == 'true' || text == '1';
  }

  static String _lastSquarefeedCursor(Map data) {
    final feeds = _findListByKey(data, 'feeds');
    for (final feed in feeds.reversed) {
      if (feed is Map) {
        final cursor = _firstString(feed, const [
          'cursorScore',
          'cursor_score',
          'cursor',
        ]);
        if (cursor.isNotEmpty) {
          return cursor;
        }
      }
    }
    return '';
  }

  static List _findListByKey(dynamic source, String key, {int depth = 0}) {
    if (depth > 8) {
      return const [];
    }
    if (source is Map) {
      final value = source[key];
      if (value is List) {
        return value;
      }
      for (final item in source.values) {
        final result = _findListByKey(item, key, depth: depth + 1);
        if (result.isNotEmpty) {
          return result;
        }
      }
    } else if (source is Iterable) {
      for (final item in source) {
        final result = _findListByKey(item, key, depth: depth + 1);
        if (result.isNotEmpty) {
          return result;
        }
      }
    }
    return const [];
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    final resolvedRoomId = resolveRoomId(roomId);
    final uri =
        Uri.parse(
          '$liveApiHost/api/sns/red/live/web/v1/room/current_room_info',
        ).replace(
          queryParameters: <String, String>{
            'room_id': resolvedRoomId,
            'request_user_id': '',
            'source': 'web_live',
            'client_type': '1',
          },
        );
    final result = await _getJson(uri);
    return parseCurrentRoomInfo(result, fallbackRoomId: resolvedRoomId);
  }

  Future<Map> _getJson(Uri uri) async {
    final fetcher = jsonFetcher;
    if (fetcher != null) {
      return fetcher(uri, null);
    }
    final result = await HttpClient.instance.getJson(
      uri.toString(),
      header: await _headersFor(uri),
    );
    return result is Map ? result : <String, dynamic>{};
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({
    required LiveRoomDetail detail,
  }) async {
    return _parseQualitiesFromStreams(_streamsFromDetail(detail));
  }

  @override
  Future<LivePlayUrl> getPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    final stream = quality.data;
    if (stream is! Map) {
      return LivePlayUrl(urls: const []);
    }
    final urls = _streamUrls(stream);
    return LivePlayUrl(urls: urls, headers: _playHeaders(detail.url));
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    return (await getRoomDetail(roomId: roomId)).status;
  }

  Future<Map<String, String>> _headersFor(Uri uri) async {
    final isWorldCupApi = uri.path.contains('/api/sns/web/worldcup/');
    final headers = <String, String>{
      'accept': 'application/json, text/plain, */*',
      'origin': webHost,
      'referer': isWorldCupApi
          ? '$webHost/worldcup26'
          : '$webHost/livestream/${resolveRoomId(uri.queryParameters['room_id'] ?? '')}',
      'user-agent': userAgent,
    };
    if (cookie.trim().isNotEmpty) {
      headers['cookie'] = cookie.trim();
    }
    final provider = signedHeadersProvider;
    if (provider != null) {
      headers.addAll(await provider(uri, null));
    }
    return headers;
  }

  Map<String, String> _playHeaders(String referer) {
    final headers = <String, String>{
      'referer': referer.isEmpty ? webHost : referer,
      'origin': webHost,
      'user-agent': userAgent,
    };
    if (cookie.trim().isNotEmpty) {
      headers['cookie'] = cookie.trim();
    }
    return headers;
  }

  static String resolveRoomId(String input) {
    final value = input.trim();
    final uri = Uri.tryParse(value);
    if (uri != null) {
      final segments = uri.pathSegments;
      final index = segments.indexOf('livestream');
      if (index >= 0 && index + 1 < segments.length) {
        return segments[index + 1];
      }
    }
    final match = RegExp(r'livestream/([^/?#]+)').firstMatch(value);
    if (match != null) {
      return match.group(1) ?? value;
    }
    return value;
  }

  static LiveRoomDetail parseCurrentRoomInfo(
    Map data, {
    required String fallbackRoomId,
  }) {
    final roomInfo = _findMapByKey(data, 'room_info') ?? data;
    final hostInfo =
        _findMapByKey(data, 'host_info') ??
        _findMapByKey(data, 'user_info') ??
        const <String, dynamic>{};
    final roomId = _firstString(roomInfo, const [
      'room_id',
      'roomId',
      'id',
    ], fallback: fallbackRoomId);
    final streams = _parsePullConfigStreams(roomInfo['pull_config']);
    final detailData = <String, dynamic>{
      'roomInfo': roomInfo,
      'hostInfo': hostInfo,
      'streams': streams,
    };
    return LiveRoomDetail(
      roomId: roomId,
      title: _firstString(roomInfo, const [
        'title',
        'name',
        'room_title',
        'room_name',
      ]),
      cover: _firstString(roomInfo, const [
        'cover',
        'cover_url',
        'room_cover',
        'image',
      ]),
      userName: _firstString(hostInfo, const ['nickname', 'nick_name', 'name']),
      userAvatar: _firstString(hostInfo, const [
        'avatar',
        'avatar_url',
        'image',
      ]),
      online: _firstInt(roomInfo, const ['online', 'online_count', 'view_num']),
      status:
          _isLiving(roomInfo['status']) ||
          _isLiving(roomInfo['live_status']) ||
          streams.isNotEmpty,
      url: '$webHost/livestream/$roomId',
      data: detailData,
      danmakuData: detailData,
    );
  }

  static LiveRoomDetail parseRoomDetailForTest(Map<String, dynamic> data) {
    final room = data['room'] is Map ? data['room'] as Map : data;
    final anchor = room['anchor'] is Map ? room['anchor'] as Map : const {};
    final streams = room['streams'] is List
        ? room['streams'] as List
        : const [];
    return LiveRoomDetail(
      roomId: _firstString(room, const ['id', 'room_id', 'roomId']),
      title: _firstString(room, const ['title']),
      cover: _firstString(room, const ['cover']),
      userName: _firstString(anchor, const ['name', 'nickname']),
      userAvatar: _firstString(anchor, const ['avatar']),
      online: _firstInt(room, const ['online']),
      status: _isLiving(room['status']),
      url: _firstString(room, const ['url']),
      data: <String, dynamic>{'streams': streams},
    );
  }

  static List<LivePlayQuality> parsePlayQualitiesForTest(
    LiveRoomDetail detail,
  ) {
    return _parseQualitiesFromStreams(_streamsFromDetail(detail));
  }

  static List<LivePlayQuality> _parseQualitiesFromStreams(List streams) {
    final playable = <Map<String, dynamic>>[];
    for (final item in streams) {
      if (item is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      if (_streamUrls(map).isEmpty) {
        continue;
      }
      playable.add(map);
    }
    playable.sort((a, b) => _streamPlayScore(b).compareTo(_streamPlayScore(a)));

    final qualities = <LivePlayQuality>[];
    for (var i = 0; i < playable.length; i++) {
      final item = playable[i];
      qualities.add(
        LivePlayQuality(
          quality: _firstString(item, const [
            'quality_type_name',
            'quality',
            'name',
          ], fallback: '线路 ${i + 1}'),
          data: item,
          sort: i,
        ),
      );
    }
    return qualities;
  }

  static List _streamsFromDetail(LiveRoomDetail detail) {
    final data = detail.data;
    if (data is Map && data['streams'] is List) {
      return data['streams'] as List;
    }
    return const [];
  }

  static List<String> _streamUrls(Map stream) {
    final urls = <String>[];
    void addUrl(dynamic value) {
      final url = value?.toString().trim() ?? '';
      if (url.startsWith('http://') || url.startsWith('https://')) {
        urls.add(url.replaceFirst('http://', 'https://'));
      }
    }

    addUrl(stream['master_url']);
    addUrl(stream['masterUrl']);
    final backups = stream['backup_urls'] ?? stream['backupUrls'];
    if (backups is Iterable) {
      for (final item in backups) {
        addUrl(item);
      }
    }
    final explicitUrls = stream['urls'];
    if (explicitUrls is Iterable) {
      for (final item in explicitUrls) {
        addUrl(item);
      }
    }
    return _sortPlayUrls(urls.toSet().toList());
  }

  static List<String> _sortPlayUrls(List<String> urls) {
    final sorted = List<String>.from(urls);
    sorted.sort((a, b) => _urlPlayScore(b).compareTo(_urlPlayScore(a)));
    return sorted;
  }

  static int _streamPlayScore(Map stream) {
    final urls = _streamUrls(stream);
    if (urls.isEmpty) {
      return 0;
    }
    return urls.map(_urlPlayScore).reduce((a, b) => a > b ? a : b);
  }

  static int _urlPlayScore(String url) {
    final value = url.toLowerCase();
    if (value.contains('hcv540')) {
      return 150;
    }
    if (value.contains('hcv520')) {
      return 145;
    }
    if (value.contains('hcv')) {
      return 140;
    }
    if (value.contains('timeshift') || value.contains('hcc')) {
      return 30;
    }
    if (value.contains('.m3u8')) {
      return 120;
    }
    if (value.contains('_orig')) {
      return 20;
    }
    if (value.contains('.flv')) {
      return 80;
    }
    return 50;
  }

  static List<Map<String, dynamic>> _parsePullConfigStreams(dynamic value) {
    if (value == null) {
      return const [];
    }
    dynamic decoded = value;
    if (value is String) {
      try {
        decoded = json.decode(value);
      } catch (_) {
        return const [];
      }
    }
    if (decoded is! Map) {
      return const [];
    }
    final streams = <dynamic>[
      if (decoded['h264_streams'] is List) ...(decoded['h264_streams'] as List),
      if (decoded['streams'] is List) ...(decoded['streams'] as List),
    ];
    if (streams.isEmpty) {
      return const [];
    }
    return streams
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Map? _findMapByKey(dynamic source, String key, {int depth = 0}) {
    if (depth > 8) {
      return null;
    }
    if (source is Map) {
      final value = source[key];
      if (value is Map) {
        return value;
      }
      for (final item in source.values) {
        final result = _findMapByKey(item, key, depth: depth + 1);
        if (result != null) {
          return result;
        }
      }
    } else if (source is Iterable) {
      for (final item in source) {
        final result = _findMapByKey(item, key, depth: depth + 1);
        if (result != null) {
          return result;
        }
      }
    }
    return null;
  }

  static String _firstString(
    Map source,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = source[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return fallback;
  }

  static int _firstInt(Map source, List<String> keys) {
    for (final key in keys) {
      final parsed = _parseCount(source[key]);
      if (parsed > 0) {
        return parsed;
      }
    }
    return 0;
  }

  static int _parseCount(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) {
      return 0;
    }
    final direct = int.tryParse(text.replaceAll(',', ''));
    if (direct != null) {
      return direct;
    }
    final wan = RegExp(r'^(\d+(?:\.\d+)?)\s*万$').firstMatch(text);
    if (wan != null) {
      final base = double.tryParse(wan.group(1) ?? '');
      if (base != null) {
        return (base * 10000).round();
      }
    }
    return 0;
  }

  static bool _isLiving(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value == 1 || value == 2 || value == 3;
    }
    final text = value?.toString().toLowerCase() ?? '';
    return text == 'true' || text == 'living' || text == 'live';
  }
}
