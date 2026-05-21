import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';

class ProfileService {
  static const _key = 'user_profile_v1';
  static UserProfile _cached = const UserProfile();
  static bool _loaded = false;

  static UserProfile get current => _cached;

  static Future<UserProfile> load() async {
    if (_loaded) return _cached;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        _cached = UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        _cached = const UserProfile();
      }
    }
    _loaded = true;
    return _cached;
  }

  static Future<void> save(UserProfile profile) async {
    _cached = profile;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(profile.toJson()));
  }

  static Future<void> clear() async {
    _cached = const UserProfile();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
