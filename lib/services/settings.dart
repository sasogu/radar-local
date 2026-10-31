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
  bool get sectionAverageWarning =>
      prefs.getBool('section_average_warning') ?? true;
  String get updateUrl {
    final configured = prefs.getString('update_url')?.trim();
    return configured == null || configured.isEmpty
        ? defaultRadarUpdateUrl
        : configured;
  }

  /// The default source is signature-checked; any other URL needs the
  /// user's explicit confirmation before it is downloaded.
  bool get updateUrlTrusted =>
      updateUrl == defaultRadarUpdateUrl ||
      prefs.getString('confirmed_update_url') == updateUrl;

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
  Future<void> setSectionAverageWarning(bool value) =>
      prefs.setBool('section_average_warning', value);
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

  Future<void> confirmUpdateUrl() =>
      prefs.setString('confirmed_update_url', updateUrl);

  /// Forgets the last download so the next one is not compared against data
  /// that came from somewhere else, such as a manual import.
  Future<void> clearUpdateCheck() => prefs.remove('last_update_check');

  Future<void> markUpdateCheck() => prefs.setString(
    'last_update_check',
    DateTime.now().toUtc().toIso8601String(),
  );
}
