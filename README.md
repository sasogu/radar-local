# Radar Local

App Flutter d'avisos de radars sense mapes. La base de dades és local i el GPS es processa al dispositiu. Idiomes: valencià/català i castellà.

## Estat

Prototip funcional Android/iOS: importació manual JSON, actualització HTTPS des de GitHub per defecte (consulta setmanal opcional amb l'app oberta), GPS, avís de veu i so, índex espacial i simulador de rutes. Inclou **1.298 avisos**: 1.056 radars (819 de la llista DGT d'agost de 2026 georeferenciats per Tachwire/IGN, 201 fixos del Servei Català de Trànsit i 36 de l'Ajuntament de Madrid) i 242 equips de detecció d'infraccions de la DGT (235 càmeres de cinturó i mòbil, 6 de línia contínua o stop i 1 foto-roig). **La cobertura continua sent parcial: el País Basc i diversos registres sense coordenades verificables queden pendents.** Consulteu les atribucions i exclusions en [DATA_SOURCES.md](DATA_SOURCES.md). No useu l'app com a únic mitjà de seguretat ni manipuleu el telèfon mentre conduïu.

Durant la conducció, quan s'acosta a un radar amb límit conegut, mostra el senyal del límit i acoloreix la velocitat: verd dins del límit, taronja dins del marge de tolerància (7 km/h o 7 %, que no és una velocitat legal) i roig a partir del llindar de multa. Si no hi ha límit conegut, no inventa cap color.

En obrir-se, l'app pot iniciar la conducció automàticament (opció activada per defecte) i demana el permís d'ubicació si cal. Mentre la conducció està activa, pot mantindre la pantalla encesa (també activat per defecte a Configuració) i la torna a alliberar en aturar. Android manté el GPS en un servei en primer pla mentre el procés de l'app continua viu. El sistema pot matar-lo; la persistència després de tancar l'app està pendent. iOS funciona amb l'app activa; el segon pla encara no està implementat ni validat. Els càlculs de velocitat mitjana dels radars de tram encara no estan disponibles: s'avisa de l'entrada del tram amb prioritat.

## Inici

```sh
flutter pub get
flutter test
flutter run
```

Des de Configuració (roda dentada) podeu importar un JSON amb l'esquema de [DATA_SOURCES.md](DATA_SOURCES.md). El fitxer `assets/data/example-radars.json` és fictici i només serveix per a proves. La URL inicial és `https://raw.githubusercontent.com/sasogu/radar-local/master/assets/data/spain-radars.json`; es pot substituir per qualsevol altra URL HTTPS amb JSON v1 i restaurar-la des de Configuració. Les actualitzacions automàtiques estan desactivades inicialment. Quan s’activen, l’app comprova les dades en obrir-se i periòdicament mentre continua oberta, com a màxim una vegada cada set dies després d’una descàrrega correcta. Pot descarregar i validar durant la conducció. En eixe cas, es mostra «Aplicar radares y reiniciar avisos»: si es prem, el GPS i els avisos es reinicien breument amb la base nova; si no, s’activa en acabar el trajecte.

El botó «Proposa un radar» permet guardar esborranys locals. Durant la conducció, «Marca possible radar» guarda un punt GPS fiable amb un toc; en acabar, es pot revisar, copiar i publicar manualment com a incidència de GitHub. Cap proposta entra automàticament a la base.

Un flux n8n diari vigila canvis en les fonts i avisa per Telegram; GitHub Actions prepara una pull request quan els convertidors detecten dades noves. La publicació de dades noves requereix revisió. Vegeu [DATA_SOURCES.md](DATA_SOURCES.md).

Consulteu [PRIVACY.md](PRIVACY.md), [ARCHITECTURE.md](ARCHITECTURE.md), [BUILDING.md](BUILDING.md), [TESTING.md](TESTING.md) i [PLAN.md](PLAN.md).
