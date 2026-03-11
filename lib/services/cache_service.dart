import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple local cache using SharedPreferences.
/// Saves user profile data and leaderboard so the app works offline.
class CacheService {
  static const _keyUserData = 'cached_user_data';
  static const _keyLeaderboard = 'cached_leaderboard';
  static const _keyAnnouncement = 'cached_announcement';
  static const _keyIsLoggedIn = 'is_logged_in';

  // ─── User Data ────────────────────────────────────────────────────────────

  static Future<void> saveUserData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserData, jsonEncode(data));
    await prefs.setBool(_keyIsLoggedIn, true);
  }

  static Future<Map<String, dynamic>?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyUserData);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ─── Leaderboard ─────────────────────────────────────────────────────────

  static Future<void> saveLeaderboard(List<Map<String, dynamic>> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLeaderboard, jsonEncode(data));
  }

  static Future<List<Map<String, dynamic>>?> getLeaderboard() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyLeaderboard);
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  // ─── Announcement ────────────────────────────────────────────────────────

  static Future<void> saveAnnouncement(String? text) async {
    final prefs = await SharedPreferences.getInstance();
    if (text != null) {
      await prefs.setString(_keyAnnouncement, text);
    } else {
      await prefs.remove(_keyAnnouncement);
    }
  }

  static Future<String?> getAnnouncement() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAnnouncement);
  }

  // ─── Session ─────────────────────────────────────────────────────────────

  /// Returns true if this device has ever had a successful login cached.
  static Future<bool> hasSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsLoggedIn) ?? false;
  }

  /// Call on logout to clear all cached data.
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserData);
    await prefs.remove(_keyLeaderboard);
    await prefs.remove(_keyAnnouncement);
    await prefs.setBool(_keyIsLoggedIn, false);
  }
}
