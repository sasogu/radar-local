# Arquitectura

`lib/core` conté el model de dades, distància i rumb geodèsics, una quadrícula espacial de 0,01° i el motor d'avisos; no depèn de Flutter. `lib/services` gestiona fitxers locals, preferències i descàrregues. `lib/main.dart` connecta el GPS, TTS i la interfície.

Per cada fix GPS, el motor exigeix una precisió horitzontal de 50 m o millor, velocitat d'almenys 3 m/s, rumb fiable i antiguitat màxima de 15 s. Descarta salts GPS impossibles. Cerca radars dins d'un radi basat en 15 s de trajecte, entre 180 i 1200 m; després comprova distància exacta, aproximació en el rumb de circulació i direcció del radar quan està disponible. Prioritza l'entrada de radars de tram i aplica cinc minuts de silenci per radar. La quadrícula redueix les comprovacions en bases grans. El filtre de 15 m del GPS i l'interval Android de 3 s redueixen consum.

L'avís de tram és només d'entrada. Un futur càlcul de velocitat mitjana requerirà punts d'inici/final georeferenciats i validats, sentit de circulació, longitud oficial, límit fiable i fixos GPS coherents al llarg del tram. No es presentarà cap estimació si falta una d'aquestes dades.

La substitució del dataset es valida abans d'escriure i es fa amb fitxer temporal. No s'apliquen actualitzacions mentre la sessió de conducció està activa. Les dades d'entrada tenen límit de 10 MB i 100.000 radars. La URL de xarxa ha de ser HTTPS.

Les propostes es guarden en preferències locals i no s'afegeixen al dataset actiu. La pantalla obri GitHub sense adjuntar coordenades a la URL; només l'usuari pot copiar-les i publicar-les. L'actualització HTTPS usa la URL GitHub per defecte, amb una URL alternativa configurable. El monitor n8n comprova empremtes de les fonts una vegada al dia i avisa si canvien. GitHub Actions executa els convertidors i obri una pull request quan el contingut canvia; la revisió editorial precedeix qualsevol publicació del JSON.
