# Roadmap

Ideas y mejoras pendientes, ordenadas por impacto. El estado validado está en
`PLAN.md`; este documento recoge lo que todavía no está hecho.

## Hecho recientemente

- Límite visible dentro del tramo y prioridad sobre radares próximos.
- Cuenta atrás hasta el final del tramo y aviso de voz «fin de tramo».
- Longitud del tramo en el aviso de entrada.
- Media estimada dentro del tramo con aviso de voz único al superar el límite.
- Activación de tramos curvos corregida usando el rumbo de entrada.
- Límites completados desde OSM: 70 tramos (115 de 129) y 33 fijos (874 de 927).

## Radares de tramo

1. **M-521 PK 26,9–27,9**: los dos extremos tienen límites distintos (60 y 70).
   Revisar el límite real antes de publicarlo; ahora queda sin límite.
2. **12 tramos sin límite fiable**: AC-552 (2), AP-9, AV-562 (2), Ma-6014,
   N-340 (2), N-403, N-525, N-550, OU-536. Buscar fuente oficial o revisión
   manual en OSM.
3. **Tramos solapados o consecutivos**: no encadenar avisos de fin/inicio con
   menos de 200 m entre ellos.
4. **Media oficial exacta**: la actual estima con distancias GPS acumuladas y
   puede saltarse los primeros metros si la entrada se detecta tarde. Para
   replicar el cálculo de la DGT haría falta la geometría real de la vía y la
   longitud oficial del tramo.
5. **Extremos de Tachwire**: algunos sentidos opuestos difieren hasta ~160 m
   (por ejemplo CL-613). Solo afecta a la distancia restante, no a los avisos.

## Datos

6. **53 radares fijos sin límite**: sin coincidencia segura en OSM. Revisión
   manual o fuente oficial.
7. **A-42 PK 55,7**: dos registros separados 8,5 km; uno tiene la longitud mal
   (-3,86466 frente a -3,96466). Corregir o eliminar el erróneo.
8. **A-4 PK 230,8**: dos registros a 1,4 km; uno sin sentido ni límite. Revisar.
9. **A-49 PK 0,5/0,7 y M-506 PK 17,715**: mismo punto, sentidos opuestos y
   límites distintos (80/60 y 80/90). Revisar.
10. **7 duplicados de Madrid** a 3–12 m con mismo nombre y límite (`madrid-1/2`,
    `4/5`, `6/7`, `8/9`, `18/19`, `21/22`, `23/24`): avisos redundantes; el
    cooldown evita el doble pitido.
11. **Foto-rojo de Madrid (37) y Málaga (5)** desde Tachwire, CC BY 4.0.
12. **Sentido de 240 fijos**: 201 SCT + 27 Madrid + 12 DGT `bothWays` sin rumbo;
    pueden avisar en sentido contrario. No hay dato oficial para corregirlo.
13. **País Basc**: no hay fuente georreferenciada equivalente a DGT/SCT.
14. **PDF de cámaras DGT**: vigilar actualizaciones (las cifras de 2026 hablan
    de más de 258 equipos; el listado oficial es de 12-2024).
15. **Capa general de límites**: descartada por peso (>10 MB). Alternativa:
    completar solo los radares sin límite.

## Aplicación

16. **iOS**: excluir las propuestas de la copia de iCloud; probar en Mac y en
    dispositivo, incluido el segundo plano.
17. **Pruebas físicas**: importación con confirmación, actualización firmada,
    aviso de base dañada, inicio automático, pantalla encendida, icono, pitido
    de paso y media del tramo.
18. **Accesibilidad**: auditoría de contraste, tamaños, etiquetas Semantics y
    TTS con TalkBack.
19. **Batería y rendimiento**: medir consumo real del GPS y del motor de avisos
    en un trayecto largo; ajustar cadencia si hace falta.
20. **Historial de avisos** de la última conducción (sin GPS guardado).
21. **Modo nocturno / brillo reducido** para la pantalla de conducción.
22. **Idioma**: revisar textos valencianos y castellanos; evitar mezclas.
23. **F-Droid**: preparar metadatos y receta una vez cerrada la beta.
