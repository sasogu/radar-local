import 'package:shared_preferences/shared_preferences.dart';

const defaultRadarUpdateUrl =
    'https://raw.githubusercontent.com/sasogu/radar-local/master/assets/data/spain-radars.json';

class AppSettings {
  AppSettings(this.prefs);
  final SharedPreferences prefs;
  String get language => prefs.getString('language') ?? 'va';
  bool get voice => prefs.getBool('voice') ?? true;
  bool get sound => prefs.getBool('sound') ?? true;
  bool get automaticUpdates => prefs.getBool('automatic_updates') ?? false;
  bool get keepScreenOn => prefs.getBool('keep_screen_on') ?? true;
  bool get autoStart => prefs.getBool('auto_start') ?? true;
  String get updateUrl {
    final configured = prefs.getString('update_url')?.trim();
    return configured == null || configured.isEmpty
        ? defaultRadarUpdateUrl
        : configured;
  }

  DateTime? get lastUpdateCheck {
    final value = prefs.getString('last_update_check');
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<void> setLanguage(String value) => prefs.setString('language', value);
  Future<void> setVoice(bool value) => prefs.setBool('voice', value);
  Future<void> setSound(bool value) => prefs.setBool('sound', value);
  Future<void> setAutomaticUpdates(bool value) =>
      prefs.setBool('automatic_updates', value);
  Future<void> setKeepScreenOn(bool value) =>
      prefs.setBool('keep_screen_on', value);
  Future<void> setAutoStart(bool value) => prefs.setBool('auto_start', value);
  Future<void> setUpdateUrl(String value) async {
    final normalized = value.trim();
    final selected = normalized.isEmpty ? defaultRadarUpdateUrl : normalized;
    if (selected == updateUrl) return;
    if (selected == defaultRadarUpdateUrl) {
      await prefs.remove('update_url');
    } else {
      await prefs.setString('update_url', selected);
    }
    await prefs.remove('last_update_check');
  }

  Future<void> markUpdateCheck() => prefs.setString(
    'last_update_check',
    DateTime.now().toUtc().toIso8601String(),
  );
}
