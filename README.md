# Radar Local

App Flutter d'avisos de radars sense mapes. La base de dades és local i el GPS es processa al dispositiu. Idiomes: valencià/català i castellà.

## Estat

Prototip funcional Android/iOS: importació manual JSON, actualització HTTPS opcional (consulta setmanal en obrir l'app), GPS, avís de veu i so, índex espacial i simulador de rutes. Inclou **1.056 radars**: 819 de la llista DGT d'agost de 2026 georeferenciats per Tachwire/IGN, 201 fixos del Servei Català de Trànsit i 36 de l'Ajuntament de Madrid. **La cobertura continua sent parcial: el País Basc i diversos registres sense coordenades verificables queden pendents.** Consulteu les atribucions i exclusions en [DATA_SOURCES.md](DATA_SOURCES.md). No useu l'app com a únic mitjà de seguretat ni manipuleu el telèfon mentre conduïu.

Android manté el GPS en un servei en primer pla mentre el procés de l'app continua viu. El sistema pot matar-lo; la persistència després de tancar l'app està pendent. iOS funciona amb l'app activa; el segon pla encara no està implementat ni validat. Els càlculs de velocitat mitjana dels radars de tram encara no estan disponibles: s'avisa de l'entrada del tram amb prioritat.

## Inici

```sh
flutter pub get
flutter test
flutter run
```

Podeu importar un JSON amb l'esquema de [DATA_SOURCES.md](DATA_SOURCES.md). El fitxer `assets/data/example-radars.json` és fictici i només serveix per a proves. Les actualitzacions automàtiques estan desactivades inicialment i, quan s'activen, només es consulten en obrir l'app fora de la conducció.

Consulteu [PRIVACY.md](PRIVACY.md), [ARCHITECTURE.md](ARCHITECTURE.md), [BUILDING.md](BUILDING.md), [TESTING.md](TESTING.md) i [PLAN.md](PLAN.md).
