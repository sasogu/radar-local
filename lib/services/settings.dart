import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  AppSettings(this.prefs);
  final SharedPreferences prefs;
  String get language => prefs.getString('language') ?? 'va';
  bool get voice => prefs.getBool('voice') ?? true;
  bool get sound => prefs.getBool('sound') ?? true;
  bool get automaticUpdates => prefs.getBool('automatic_updates') ?? false;
  String get updateUrl => prefs.getString('update_url') ?? '';
  DateTime? get lastUpdateCheck {
    final value = prefs.getString('last_update_check');
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<void> setLanguage(String value) => prefs.setString('language', value);
  Future<void> setVoice(bool value) => prefs.setBool('voice', value);
  Future<void> setSound(bool value) => prefs.setBool('sound', value);
  Future<void> setAutomaticUpdates(bool value) =>
      prefs.setBool('automatic_updates', value);
  Future<void> setUpdateUrl(String value) =>
      prefs.setString('update_url', value);
  Future<void> markUpdateCheck() => prefs.setString(
    'last_update_check',
    DateTime.now().toUtc().toIso8601String(),
  );
}
