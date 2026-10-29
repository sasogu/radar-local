# Proves

```sh
flutter analyze
flutter test
dart run tool/simulate_route.dart assets/data/example-radars.json assets/data/example-route.json
flutter build apk --debug
```

Les proves unitàries cobreixen distància/rumb, índex, avís, silenci, filtres de falsos positius, prioritat de trams i validació JSON, URL predeterminada i persistència de propostes. La prova d’integració valida la base real empaquetada i les proves de servei comproven que una actualització preparada no substitueix la base activa fins a aplicar-la. El simulador reprodueix una llista de fixos GPS i imprimeix els avisos. `seconds` és relatiu a l'inici; `speed` és en m/s i `heading` en graus. Les coordenades d'exemple són fictícies.

Abans d'una publicació cal una prova d'integració en dispositiu Android i iPhone: permisos, GPS real, pantalla apagada, interrupcions TTS, notificació de servei, consum de bateria, importació, actualització HTTPS i funcionament sense cobertura. No s'han executat proves en dispositiu en aquest entorn.
