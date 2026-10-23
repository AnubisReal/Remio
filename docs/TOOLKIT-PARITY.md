# Herramientas de Remio y referencia Android

## Organización

La pestaña se llama Herramientas. Sus pantallas nativas son Dispositivos, Aplicaciones, Lotes de APK, Fotos, Copias, Información del Portal, Actualizaciones e Historial. El mando y sus sesiones HTTP siguen separados.

## Funciones implementadas

| Portal Toolkit Android | Remio iOS |
|---|---|
| ADB TCP/IP y dispositivos guardados | Identidad RSA en llavero, reconexión, destinos guardados, nombres locales, selector común |
| Información del dispositivo | Fabricante, modelo, Android/SDK, memoria y almacenamiento por consultas ADB |
| Lista de apps, versiones, desinstalación | Paquetes de terceros, nombres de la API remota cuando existen, detalles de versión, confirmación para desinstalar |
| Instalar APK personalizado | Selector Archivos, transferencia SYNC y pm install -r, confirmación explícita |
| Perfiles de apps | Lotes locales de archivos APK guardados en el contenedor de Remio, instalación secuencial confirmada |
| Subir fotos | Fototeca o Archivos, SYNC a Pictures/Remio y solicitud de indexación multimedia |
| Copia y restauración ZIP | Manifiesto formato 1, APK base/splits y la misma lista de siete ajustes básicos, selección de apps, exportación Archivos y validación antes de restaurar |
| Actualizaciones OTA | Los mismos dos paquetes compatibles del Android; consulta, bloqueo y reactivación confirmados y verificados |
| Historial | Últimas 100 acciones de herramientas guardadas localmente |

## Diferencias y límites

- iOS no permite extraer APK de aplicaciones instaladas en el iPhone. Los lotes se crean importando APK desde Archivos.
- No se ha implementado USB OTG ni activar ADB desde USB en iOS. En el Portal actual se utiliza ADB por Wi-Fi ya habilitado. Buscar/añadir abre el selector común de Portal; no hay barrido de una subred por ADB.
- Los nombres de destinos solo cambian en Remio. Una conexión ADB activa a la vez. No se revoca la clave global al olvidar un destino.
- Las copias no incluyen datos privados de apps, cuentas ni fotos. El ZIP y los archivos se limitan a 256 MB. La restauración exige mismo modelo y SDK, y los ajustes están desactivados por defecto.
- El ZIP usa STORE al exportar y acepta STORE/DEFLATE al importar. Se comprueban rutas, duplicados, tamaños y CRC. No acepta cifrado, ZIP64 ni archivos de varios volúmenes. No se extraen rutas a disco al importar.
- La APK personalizada se comprueba como ZIP y queda sujeta a la validación de firma/paquete/SDK del instalador Android; no se interpreta AndroidManifest binario previamente. Los lotes son APK completos independientes; los splits se restauran desde una copia mediante sesión install-create/write/commit.
- La restauración o instalación de un lote se detiene al primer fallo; las apps que ya terminaron no se desinstalan para simular rollback.

## Separación y seguridad de operaciones

Las consultas comprueban primero que el equipo ADB se identifica como Portal. No hay consola arbitraria ni comandos introducidos por el usuario. Se validan nombres de paquete, se escapan argumentos de shell, se usan destinos de escritura fijos o temporales UUID, y se eliminan los temporales de instalación tras el intento. La app no inicia ninguna operación de modificación al conectar.

Aplicaciones, actualización OTA y restauración requieren confirmación. Desinstalar borra datos y se indica en la confirmación. La desinstalación directa de com.immortal.launcher se bloquea para conservar el mando. La conexión/llavero del mando no cambia con estas herramientas.

ADB usa un canal por operación con IDs y ACK, checksum clásico, límite de respuesta, timeout, cancelación y descarte de callbacks antiguos. SYNC procesa mensajes fragmentados de forma incremental. No se reenvían automáticamente operaciones interrumpidas.

## Validación realizada

- Compilación nativa iOS Simulator.
- Pruebas de regresión del mando y autenticación, framing de streams, SYNC fragmentado, límites de comandos, ZIP roundtrip/CRC/rutas y un ZIP DEFLATE generado con Python (como el Android).
- Prueba real de solo lectura desde Remio: 7 campos de información y 16 apps obtenidos del Portal autorizado.
- Revisión visual de la pantalla principal de Herramientas.

## Pendiente de validación en hardware

No se han instalado/desinstalado apps, subido fotos, bloqueado actualizaciones ni restaurado copias en el Portal del propietario. Las rutas están implementadas pero aún requieren pruebas controladas con archivos elegidos por él. Tampoco se ha verificado el intercambio de una copia completa con Portal Toolkit; el formato y la descompresión sí se prueban localmente.
