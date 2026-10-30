# Proves

```sh
flutter analyze
flutter test
dart run tool/simulate_route.dart assets/data/example-radars.json assets/data/example-route.json
flutter build apk --debug
```

Les proves unitàries cobreixen distància/rumb, índex, avís, silenci, filtres de falsos positius, prioritat de trams, avís de càmeres de cinturó i mòbil, zones de velocitat (7 km/h o 7 %), límit del radar pròxim i validació JSON (incloent-hi tipus desconeguts i bases buides), signatura de la base publicada, rebuig d’actualitzacions sospitoses, recuperació d’una base malmesa, confirmació d’URL pròpies, URL predeterminada i persistència de propostes (també amb esborranys malmesos). La prova d’integració valida la base real empaquetada i les proves de servei comproven que una actualització preparada no substitueix la base activa fins a aplicar-la. El simulador reprodueix una llista de fixos GPS i imprimeix els avisos. `seconds` és relatiu a l'inici; `speed` és en m/s i `heading` en graus. Les coordenades d'exemple són fictícies.

Abans d'una publicació cal una prova d'integració en dispositiu Android i iPhone: permisos, inici automàtic en obrir, GPS real, pantalla encesa durant la conducció i apagada en aturar, interrupcions TTS, notificació de servei, consum de bateria, importació, actualització HTTPS i funcionament sense cobertura. No s'han executat proves en dispositiu en aquest entorn.
