import 'package:flutter/foundation.dart';
import 'package:flutter_carplay/flutter_carplay.dart';

import 'car_state.dart';

/// Builds the informational pane shown on the Android Auto display.
///
/// Android Auto templates are native, so the screen is deliberately limited to
/// read-only rows plus one start/stop action. The same [id] must be reused when
/// updating the pane, otherwise the host treats it as a new template.
AAPaneTemplate buildCarPane({
  required CarSnapshot snapshot,
  required String id,
  required VoidCallback onStart,
  required VoidCallback onStop,
}) {
  String tr(String va, String es) => snapshot.isCatalan ? va : es;

  final items = <AAPaneItem>[
    AAPaneItem(title: tr('Velocitat', 'Velocidad'), detail: snapshot.speed),
    AAPaneItem(title: tr('Límit', 'Límite'), detail: snapshot.limit),
    AAPaneItem(
      title: tr('Avis', 'Aviso'),
      detail: snapshot.alert.isEmpty
          ? tr('Sense avisos', 'Sin avisos')
          : snapshot.alert,
    ),
    AAPaneItem(
      title: tr('Tram', 'Tramo'),
      detail: snapshot.section.isEmpty ? '—' : snapshot.section,
    ),
    AAPaneItem(
      title: tr('Estat', 'Estado'),
      detail: snapshot.status.isEmpty
          ? tr('Esperant dades', 'Esperando datos')
          : snapshot.status,
    ),
    AAPaneItem(
      title: tr('Base', 'Base'),
      detail: snapshot.base.isEmpty ? '—' : snapshot.base,
    ),
  ];

  final actions = <AAPaneAction>[
    if (snapshot.driving)
      AAPaneAction(title: tr('Atura', 'Detener'), onPress: onStop)
    else
      AAPaneAction(
        title: tr('Inicia', 'Iniciar'),
        isPrimary: true,
        onPress: onStart,
      ),
  ];

  return AAPaneTemplate(
    id: id,
    title: tr('Radar Local', 'Radar Local'),
    items: items,
    actions: actions,
  );
}
