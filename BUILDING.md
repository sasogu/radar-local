# Compilació i publicació

Requisits: Flutter 3.35 o compatible, Dart 3.9, Android SDK per a APK i Android App Bundle. Executeu des d'aquest directori:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release
flutter build appbundle --release
```

La variant de publicació necessita un certificat propi i `signingConfig` configurat localment; no es guarda cap clau al repositori. Reviseu l'identificador `org.daizan.radar_local`, nom, icones, versió i metadades abans de publicar. El build de depuració és per a proves, no per distribuir. Per a F-Droid, el Gradle exclou Google Play Services i el GPS usa el proveïdor Android. Verifiqueu dependències, llicències i compilació reproduïble amb la infraestructura F-Droid abans d'enviar metadades. Publiqueu codi i documentació a GitHub només després de revisar llicències, dades i fitxers sensibles.

**iOS requereix macOS amb Xcode**, un compte Apple Developer i signatura/provisioning per compilar, provar en dispositiu i enviar a App Store. Des d'aquest Linux no es pot generar ni validar l'IPA. Abans de publicar iOS, completeu i valideu l'execució en segon pla, les descripcions de privacitat, captures, icones i les proves en dispositiu.
