# Roadmap

Ideas y mejoras pendientes, ordenadas por impacto. El estado validado está en
`PLAN.md`; este documento recoge lo que todavía no está hecho.

## Hecho recientemente

- Límite visible dentro del tramo y prioridad sobre radares próximos.
- Cuenta atrás hasta el final del tramo y aviso de voz «fin de tramo».
- Media estimada con entrada/salida interpoladas y longitud oficial de la DGT.
- Media necesaria sobre lo que queda para acabar dentro del límite.
- Pitido grave al pasar el radar (sin voz).
- Activación de tramos curvos usando el rumbo de entrada.
- 59 sentidos inferidos desde OSM para radares fijos.
- Límites completados desde OSM: 70 tramos (115 de 129) y 33 fijos (874 de 927).
- Corregida la longitud errónea de A-42 PK 55,7.
- Aviso de responsabilidad en el primer arranque y pantalla de aviso legal.

## Radares de tramo

1. **M-521 PK 26,9–27,9**: los dos extremos tienen límites distintos (60 y 70).
   Revisar el límite real antes de publicarlo; ahora queda sin límite.
2. **12 tramos sin límite fiable**: AC-552 (2), AP-9, AV-562 (2), Ma-6014,
   N-340 (2), N-403, N-525, N-550, OU-536. Buscar fuente oficial o revisión
   manual en OSM.
3. **Tramos solapados o consecutivos**: no encadenar avisos de fin/inicio con
   menos de 200 m entre ellos.
4. **Media más exacta**: ya usa la longitud oficial, pero la distancia recorrida
   sigue siendo GPS acumulado. Para replicar del todo a la DGT haría falta la
   geometría real de la vía.
5. **Extremos de Tachwire**: algunos sentidos opuestos difieren hasta ~160 m
   (por ejemplo CL-613). Solo afecta a la distancia restante, no a los avisos.

## Datos

6. **53 radares fijos sin límite**: sin coincidencia segura en OSM. Revisión
   manual o fuente oficial.
7. **181 fijos sin sentido**: 168 SCT + 1 Madrid + 12 DGT `bothWays`. Los 59
   inferidos usan el lado derecho de la calzada; los demás avisan en ambos
   sentidos. No hay dato oficial para el resto.
8. **A-4 PK 230,8, A-49 PK 0,5/0,7 y M-506 PK 17,715**: revisados; se mantienen
   porque OSM confirma límites distintos por calzada o la transición de límite.
9. **7 pares de Madrid a 3–12 m**: son cámaras de carriles distintos, no
   duplicados; se conservan. El cooldown evita el doble pitido.
10. **Foto-rojo de Madrid (37) y Málaga (5)** desde Tachwire, CC BY 4.0.
11. **País Basc**: no hay fuente georreferenciada equivalente a DGT/SCT.
12. **PDF de cámaras DGT**: vigilar actualizaciones (las cifras de 2026 hablan
    de más de 258 equipos; el listado oficial es de 12-2024).
13. **Capa general de límites**: descartada por peso (>10 MB). Alternativa:
    completar solo los radares sin límite.

## Aplicación

14. **iOS**: excluir las propuestas de la copia de iCloud; probar en Mac y en
    dispositivo, incluido el segundo plano.
15. **Pruebas físicas**: importación con confirmación, actualización firmada,
    aviso de base dañada, inicio automático, pantalla encendida, icono, pitido
    de paso, media y aviso de media necesaria.
16. **Accesibilidad**: auditoría de contraste, tamaños, etiquetas Semantics y
    TTS con TalkBack.
17. **Batería y rendimiento**: medir consumo real del GPS y del motor de avisos
    en un trayecto largo; ajustar cadencia si hace falta.
18. **Historial de avisos** de la última conducción (sin GPS guardado).
19. **Modo nocturno / brillo reducido** para la pantalla de conducción.
20. **Idioma**: revisar textos valencianos y castellanos; evitar mezclas.
21. **F-Droid**: preparar metadatos y receta una vez cerrada la beta.
