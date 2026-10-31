# Roadmap

Ideas y mejoras pendientes, ordenadas por impacto. El estado validado está en
`PLAN.md`; este documento recoge lo que todavía no está hecho.

## Hecho recientemente

- Límite visible dentro del tramo y prioridad sobre radares próximos.
- Cuenta atrás hasta el final del tramo y aviso de voz «fin de tramo».
- Longitud del tramo en el aviso de entrada.
- Límites completados desde OSM para 70 tramos (115 de 129 con límite).
- Media estimada dentro del tramo con aviso de voz único al superar el límite.

## Radares de tramo

1. **M-521 PK 26,9–27,9**: los dos extremos tienen límites distintos (60 y 70).
   Revisar el límite real antes de publicarlo; ahora queda sin límite.
2. **12 tramos sin límite fiable**: AC-552 (2), AP-9, AV-562 (2), Ma-6014,
   N-340 (2), N-403, N-525, N-550, OU-536. Buscar fuente oficial o revisión
   manual en OSM.
3. **Sentido del tramo.** Revisar los tramos con `direction` ausente o dudoso:
   no avisar en sentido contrario.
4. **Tramos solapados o consecutivos**: no encadenar avisos de fin/inicio con
   menos de 200 m entre ellos.
5. **Media oficial exacta**: la actual estima con distancias GPS acumuladas y
   puede saltarse los primeros metros si la entrada se detecta tarde. Para
   replicar el cálculo de la DGT haría falta la geometría real de la vía y la
   longitud oficial del tramo.

## Datos

6. **Foto-rojo de Madrid (37) y Málaga (5)** desde Tachwire, CC BY 4.0.
7. **Auditar sentidos** de radares fijos que las fuentes no dan numéricamente.
8. **País Basc**: no hay fuente georreferenciada equivalente a DGT/SCT.
9. **PDF de cámaras DGT**: vigilar actualizaciones (las cifras de 2026 hablan
   de más de 258 equipos; el listado oficial es de 12-2024).
10. **Capa general de límites**: descartada por peso (>10 MB). Alternativa:
    completar solo los radares sin límite, como se ha hecho con los tramos.

## Aplicación

11. **iOS**: excluir las propuestas de la copia de iCloud; probar en Mac y en
    dispositivo, incluido el segundo plano.
12. **Pruebas físicas v0.1.9**: importación con confirmación, actualización
    firmada, aviso de base dañada, inicio automático, pantalla encendida e
    icono.
13. **Accesibilidad**: auditoría de contraste, tamaños, etiquetas Semantics y
    TTS con TalkBack.
14. **Batería y rendimiento**: medir consumo real del GPS y del motor de avisos
    en un trayecto largo; ajustar cadencia si hace falta.
15. **Historial de avisos** de la última conducción (sin GPS guardado).
16. **Modo nocturno / brillo reducido** para la pantalla de conducción.
17. **Idioma**: revisar textos valencianos y castellanos; evitar mezclas.
18. **F-Droid**: preparar metadatos y receta una vez cerrada la beta.
