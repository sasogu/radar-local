import 'package:flutter_test/flutter_test.dart';
import 'package:radar_local/core/proposal.dart';
import 'package:radar_local/core/radar.dart';
import 'package:radar_local/services/proposal_store.dart';
import 'package:radar_local/services/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('default update URL can be overridden and restored', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    expect(settings.updateUrl, defaultRadarUpdateUrl);
    await settings.markUpdateCheck();
    await settings.setUpdateUrl(' https://example.org/radars.json ');
    expect(settings.updateUrl, 'https://example.org/radars.json');
    expect(settings.lastUpdateCheck, isNull);
    await settings.setUpdateUrl('');
    expect(settings.updateUrl, defaultRadarUpdateUrl);
  });

  test('custom update URLs need confirmation', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    expect(settings.updateUrlTrusted, isTrue);
    await settings.setUpdateUrl('https://example.org/radars.json');
    expect(settings.updateUrlTrusted, isFalse);
    await settings.confirmUpdateUrl();
    expect(settings.updateUrlTrusted, isTrue);
    await settings.setUpdateUrl('https://example.org/other.json');
    expect(settings.updateUrlTrusted, isFalse);
  });

  test('damaged proposals do not hide valid ones', () async {
    SharedPreferences.setMockInitialValues({
      'radar_proposals_v1':
          '[{"id":"bad"},{"id":"ok","point":{"lat":39.4,"lon":-0.3},'
          '"created_at":"2026-10-30T00:00:00Z","kind":"fixed"}]',
    });
    final store = ProposalStore(await SharedPreferences.getInstance());
    expect(store.all().single.id, 'ok');
    SharedPreferences.setMockInitialValues({'radar_proposals_v1': '{oops'});
    expect(ProposalStore(await SharedPreferences.getInstance()).all(), isEmpty);
  });

  test('auto start defaults to true and can be disabled', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    expect(settings.autoStart, isTrue);
    await settings.setAutoStart(false);
    expect(settings.autoStart, isFalse);
  });
  test('keep screen on defaults to true and can be disabled', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    expect(settings.keepScreenOn, isTrue);
    await settings.setKeepScreenOn(false);
    expect(settings.keepScreenOn, isFalse);
  });
  test('proposal persists locally and can be removed', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = ProposalStore(prefs);
    final proposal = RadarProposal(
      id: 'sample',
      point: const Point(39.47, -0.37),
      createdAt: DateTime.utc(2026, 10, 29),
      accuracy: 12,
      note: 'Revisar font oficial',
    );
    await store.save(proposal);
    expect(ProposalStore(prefs).all().single.point.lat, 39.47);
    expect(ProposalStore(prefs).all().single.note, 'Revisar font oficial');
    await store.remove('sample');
    expect(store.all(), isEmpty);
  });
}
