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
    final Object? entries;
    try {
      entries = jsonDecode(raw);
    } on FormatException {
      return [];
    }
    if (entries is! List) return [];
    // One damaged draft must not hide or block the others.
    final proposals = <RadarProposal>[];
    for (final entry in entries) {
      try {
        proposals.add(RadarProposal.fromJson(entry as Map<String, dynamic>));
      } catch (_) {}
    }
    return proposals;
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
