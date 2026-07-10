class XiaohongshuCookieHelper {
  static bool isLoggedIn(Map<String, String> cookies) {
    return (cookies['web_session'] ?? '').trim().isNotEmpty;
  }

  static String serialize(Map<String, String> cookies) {
    final entries =
        cookies.entries
            .where(
              (entry) => entry.key.trim().isNotEmpty && entry.value.isNotEmpty,
            )
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
  }
}
