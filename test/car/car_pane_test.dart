import 'package:flutter_test/flutter_test.dart';
import 'package:radar_local/car/car_pane.dart';
import 'package:radar_local/car/car_state.dart';

void main() {
  const base = CarSnapshot(
    language: 'es',
    driving: false,
    speed: '87 km/h',
    limit: '90 km/h',
    alert: 'Radar · 350 m',
    section: '',
    status: 'GPS activo',
    base: '1298 avisos',
  );

  test('stopped pane offers the start action and core rows', () {
    var started = false;
    var stopped = false;
    final pane = buildCarPane(
      snapshot: base,
      id: 'pane-test',
      onStart: () => started = true,
      onStop: () => stopped = true,
    );

    expect(pane.uniqueId, 'pane-test');
    expect(pane.title, 'Radar Local');
    expect(
      pane.items.map((item) => item.title),
      containsAll(<String>['Velocidad', 'Límite', 'Aviso', 'Estado', 'Base']),
    );
    expect(pane.items.first.detail, '87 km/h');
    expect(pane.items[1].detail, '90 km/h');
    expect(pane.items[2].detail, 'Radar · 350 m');
    expect(pane.actions.single.title, 'Iniciar');
    expect(pane.actions.single.isPrimary, isTrue);

    pane.actions.single.onPress!();
    expect(started, isTrue);
    expect(stopped, isFalse);
  });

  test('driving pane shows the section and the stop action', () {
    var stopped = false;
    final pane = buildCarPane(
      snapshot: const CarSnapshot(
        language: 'va',
        driving: true,
        speed: '92 km/h',
        limit: '90 km/h',
        alert: 'Tram actiu · queden 1,2 km',
        section: 'Tram actiu · queden 1,2 km · mitjana 88 km/h',
        status: 'GPS actiu',
        base: '1298 avisos',
      ),
      id: 'pane-test',
      onStart: () {},
      onStop: () => stopped = true,
    );

    expect(pane.items.map((item) => item.title), contains('Tram'));
    expect(pane.actions.single.title, 'Atura');
    expect(pane.actions.single.isPrimary, isFalse);

    pane.actions.single.onPress!();
    expect(stopped, isTrue);
  });

  test('empty optional values stay readable', () {
    final pane = buildCarPane(
      snapshot: CarSnapshot.empty,
      id: 'pane-test',
      onStart: () {},
      onStop: () {},
    );

    expect(pane.items.map((item) => item.title), contains('Tram'));
    expect(pane.items[2].detail, 'Sense avisos');
    expect(pane.items[3].detail, '—');
    expect(pane.items[4].detail, 'Esperant dades');
    expect(pane.items[5].detail, '—');
  });

  test('snapshot equality ignores no fields', () {
    expect(
      const CarSnapshot(
        language: 'es',
        driving: false,
        speed: '1',
        limit: '2',
        alert: '3',
        section: '4',
        status: '5',
        base: '6',
      ),
      const CarSnapshot(
        language: 'es',
        driving: false,
        speed: '1',
        limit: '2',
        alert: '3',
        section: '4',
        status: '5',
        base: '6',
      ),
    );
    expect(
      CarSnapshot.empty,
      isNot(
        const CarSnapshot(
          language: 'es',
          driving: false,
          speed: '1',
          limit: '2',
          alert: '3',
          section: '4',
          status: '5',
          base: '6',
        ),
      ),
    );
  });
}
