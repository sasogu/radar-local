import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/proposal.dart';

class ProposalStore {
  ProposalStore(this.prefs);
  final SharedPreferences prefs;
  static const _key = 'radar_proposals_v1';

  List<RadarProposal> all() {
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final entries = jsonDecode(raw) as List<dynamic>;
    return entries
        .map((e) => RadarProposal.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(RadarProposal proposal) async {
    proposal.validate();
    final proposals = all();
    final index = proposals.indexWhere((p) => p.id == proposal.id);
    if (index >= 0) {
      proposals[index] = proposal;
    } else {
      if (proposals.length >= 100) {
        throw StateError('Too many saved proposals');
      }
      proposals.insert(0, proposal);
    }
    await prefs.setString(
      _key,
      jsonEncode(proposals.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> remove(String id) async {
    final proposals = all()..removeWhere((p) => p.id == id);
    await prefs.setString(
      _key,
      jsonEncode(proposals.map((p) => p.toJson()).toList()),
    );
  }
}
