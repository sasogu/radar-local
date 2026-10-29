# Fonts de dades

La còpia inicial inclou 36 radars (27 fixos i 9 de tram) del [catàleg oficial de l'Ajuntament de Madrid](https://datos.madrid.es/dataset/300049-0-radares-fijos-moviles) i del seu [CSV oficial](https://datos.madrid.es/dataset/300049-0-radares-fijos-moviles/resource/300049-1-radares-fijos-moviles-csv/download/300049-1-radares-fijos-moviles-csv.csv), consultat el 29-10-2026. El [catàleg de datos.gob.es](https://datos.gob.es/es/catalogo/l01280796-radares1) indica coordenades WGS84 i condicions [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/legalcode.es). **Atribució:** Ajuntament de Madrid, «Radares», dades reutilitzades sota CC BY 4.0. Les dades derivades en `assets/data/madrid-radars.json` conserven aquesta atribució; la llicència MIT del codi no les substitueix.

El convertidor `tool/convert_madrid.py` transforma el CSV oficial a l'esquema v1. Els radars de tram usen el punt inicial i final i calculen el rumb geomètric entre tots dos. Per als fixos, el CSV dona el sentit com a text, no en graus: el convertidor deixa `direction` buit per no inventar-lo. Això pot provocar avisos en vies paral·leles o en l'altre sentit. La cobertura és només Madrid; la còpia és una fotografia de la data de consulta i no s'actualitza sense tornar a importar un fitxer. L'URL d'actualització de l'app exigeix JSON v1 i no admet el CSV directament.

Per ampliar cobertura, cal documentar per a cada font URL oficial, data de consulta, llicència, àmbit geogràfic, qualitat de coordenades i validació del sentit. El [Punt d'Accés Nacional de la DGT](https://nap.dgt.es/es/dataset/radares-fijos-dgt) publica radars fixos en DATEX II fora de Catalunya i el País Basc; cal un convertidor i verificació abans d'incorporar-los. Eviteu atribuir un rumb per inferència si no és fiable.

Format JSON v1:

```json
{
  "schema": 1,
  "source": "Nom i llicència de la font",
  "updated_at": "2026-10-29T00:00:00Z",
  "radars": [
    {"id":"id-estable", "kind":"fixed", "start":{"lat":39.47,"lon":-0.37}, "direction":90, "speed_limit":80, "name":"Opcional"},
    {"id":"tram-1", "kind":"section", "start":{"lat":39.48,"lon":-0.37}, "end":{"lat":39.49,"lon":-0.37}, "direction":0}
  ]
}
```

`kind` accepta `fixed`, `redLight` i `section`. `direction` és el rumb de circulació en graus des del nord (0–359), opcional si la font no el coneix. Els radars de tram exigeixen `end`; actualment s'avisa de l'entrada, sense càlcul de mitjana. Els IDs han de ser únics. Les coordenades són WGS84. L'exemple inclòs és fictici i no s'ha de distribuir com a dades reals.
