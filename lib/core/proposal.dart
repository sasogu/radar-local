import 'radar.dart';

enum ProposedRadarKind { unknown, fixed, section, redLight }

class RadarProposal {
  const RadarProposal({
    required this.id,
    required this.point,
    required this.createdAt,
    this.kind = ProposedRadarKind.unknown,
    this.accuracy,
    this.heading,
    this.note = '',
  });

  final String id;
  final Point point;
  final DateTime createdAt;
  final ProposedRadarKind kind;
  final double? accuracy;
  final double? heading;
  final String note;

  RadarProposal copyWith({ProposedRadarKind? kind, String? note}) =>
      RadarProposal(
        id: id,
        point: point,
        createdAt: createdAt,
        kind: kind ?? this.kind,
        accuracy: accuracy,
        heading: heading,
        note: note ?? this.note,
      );

  void validate() {
    if (id.isEmpty ||
        !point.lat.isFinite ||
        !point.lon.isFinite ||
        point.lat.abs() > 90 ||
        point.lon.abs() > 180 ||
        (accuracy != null &&
            (!accuracy!.isFinite || accuracy! < 0 || accuracy! > 1000)) ||
        (heading != null &&
            (!heading!.isFinite || heading! < 0 || heading! >= 360)) ||
        note.length > 500) {
      throw const FormatException('Invalid radar proposal');
    }
  }

  factory RadarProposal.fromJson(Map<String, dynamic> json) {
    final proposal = RadarProposal(
      id: json['id'] as String,
      point: Point.fromJson(json['point'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['created_at'] as String),
      kind: ProposedRadarKind.values.byName(json['kind'] as String),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
      note: (json['note'] as String?) ?? '',
    );
    proposal.validate();
    return proposal;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'point': point.toJson(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'kind': kind.name,
    if (accuracy != null) 'accuracy': accuracy,
    if (heading != null) 'heading': heading,
    if (note.isNotEmpty) 'note': note,
  };
}
