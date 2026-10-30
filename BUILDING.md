# Compilació i publicació

Requisits: Flutter 3.35 o compatible, Dart 3.9, Android SDK per a APK i Android App Bundle. Executeu des d'aquest directori:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
./tool/build_signed_android.sh
```

La variant de publicació necessita les variables `RADAR_RELEASE_STORE_FILE`, `RADAR_RELEASE_STORE_PASSWORD`, `RADAR_RELEASE_KEY_ALIAS` i `RADAR_RELEASE_KEY_PASSWORD`. Gradle no compila una variant `Release` sense aquestes variables. La clau de Radar Local està guardada fora del repositori, a `~/.local/share/radar-local/android-release.p12` (permís 600); la contrasenya i una còpia xifrada de la clau estan en `pass` sota `radar-local/android-release` i `radar-local/android-release-keystore`. El script local `tool/build_signed_android.sh` carrega la contrasenya en memòria i compila l'APK. No es guarda cap clau al repositori.

Els icones d'Android i iOS es regeneren amb `./tool/make_icons.sh` (requereix Inkscape i ImageMagick) a partir de `assets/icon/icon.svg` i `assets/icon/icon-foreground.svg`.

Reviseu l'identificador `org.daizan.radar_local`, nom, icones, versió i metadades abans de publicar. Els dispositius amb l'APK anterior signat amb clau de depuració hauran de desinstal·lar-lo abans d'instal·lar la versió signada de producció; Android no permet actualitzar entre certificats diferents. Per a F-Droid, el Gradle exclou Google Play Services i el GPS usa el proveïdor Android. Verifiqueu dependències, llicències i compilació reproduïble amb la infraestructura F-Droid abans d'enviar metadades.

**iOS requereix macOS amb Xcode**, un compte Apple Developer i signatura/provisioning per compilar, provar en dispositiu i enviar a App Store. Des d'aquest Linux no es pot generar ni validar l'IPA. Abans de publicar iOS, completeu i valideu l'execució en segon pla, les descripcions de privacitat, captures, icones i les proves en dispositiu.
