# Pla incremental

1. **Arquitectura:** model, separació core/serveis/UI — fet; analitzar i provar.
2. **Dades:** JSON local, validació, importació i actualització opcional — fet; compilar Android.
3. **Motor:** distància, rumb, velocitat, precisió, sentit i silenci — fet; proves unitàries.
4. **GPS:** flux de posicions i permisos — implementat; pendent prova física.
5. **Alertes:** veu i so configurables — implementat; pendent prova física de TTS.
6. **Segon pla Android:** servei en primer pla mentre el procés viu — implementat; pendent supervivència després de tancar el procés.
7. **Interfície:** pantalla sense mapes, botons grans, dos idiomes i anuncis accessibles — implementat; pendent auditoria d'accessibilitat.
8. **Fonts reals:** 819 de la llista DGT 2026 georeferenciats per Tachwire/IGN, 201 fixos de Catalunya i 36 de Madrid incorporats. Pendent una font georeferenciada del País Basc i els registres DGT/SCT sense coordenades verificables; no hi ha cobertura estatal completa. Cal auditar sentits dels fixos que les fonts no donen numèricament.
9. **Integració iOS:** esquelet i permís d'ús actiu — implementat; pendent macOS, dispositiu i segon pla.
10. **Optimització:** índex espacial, filtre de distància i cadència GPS — implementat; pendent mesura de bateria i rendiment en dispositiu.
11. **Publicació:** instruccions GitHub/F-Droid/APK/App Store — redactades; pendent signatura, metadades, proves físiques i enviaments.

Cada fase s'ha d'analitzar, provar i compilar al sistema disponible abans de considerar-la tancada. Els punts pendents no es consideren funcionalitat validada.
