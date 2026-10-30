# Vigilància de fonts amb n8n

El flux `n8n-radar-sources.json` comprova cada dia la llista PDF oficial DGT, el PDF d'equips de detecció d'infraccions i els fitxers de Tachwire, SCT i Madrid. Desa només les empremtes SHA-256 en `/home/node/.n8n/radar-sources-state.json` i avisa per Telegram si detecta un canvi o un error nou. La primera execució crea la referència. No publica dades ni rep coordenades GPS dels usuaris.

El JSON del repositori és una plantilla sense credencials ni identificador de xat. Després d'importar-lo en n8n, cal seleccionar una credencial Telegram pròpia i configurar el xat destinatari. La instal·lació actual del servidor ja està configurada i activa amb el nom `Radar Local · vigilar novetats de fonts`.

El fitxer `check-radar-sources.js` és la còpia llegible del node Code. Si es modifica, cal actualitzar també el camp `jsCode` del JSON i tornar a publicar el flux en n8n. El fitxer d'estat és local al volum d'n8n; no forma part del repositori.

GitHub Actions executa `tool/refresh_sources.py` per separat i crea una pull request amb els JSON candidats si les dades canvien. Cal revisar-la i fusionar-la abans que la URL predeterminada de l'app servisca les dades noves.
