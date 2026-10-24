# Herramientas de Remio y referencia Android

## Organización

La pestaña se llama Herramientas. Sus pantallas nativas son Dispositivos, Aplicaciones, Lotes de APK, Fotos, Copias, Información del Portal, Actualizaciones e Historial. El mando y sus sesiones HTTP siguen separados.

## Funciones implementadas

| Portal Toolkit Android | Remio iOS |
|---|---|
| ADB TCP/IP y dispositivos guardados | Identidad RSA en llavero, reconexión, destinos guardados, nombres locales, selector común |
| Información del dispositivo | Fabricante, modelo, Android/SDK, memoria y almacenamiento por consultas ADB |
| Lista de apps, versiones, desinstalación | Paquetes de terceros, iconos y nombres remotos, versión/tamaño en la lista, orden por tamaño y confirmación de desinstalación |
| Instalar APK personalizado | Selector Archivos, inspección de manifiesto binario, comprobación de SDK real, transferencia SYNC y pm install -r, confirmación explícita |
| Perfiles de apps | Lotes locales de archivos APK guardados en el contenedor de Remio, instalación secuencial confirmada |
| Subir fotos | Fototeca o Archivos, miniaturas, aviso central Enviar/Cancelar, comprobación de formato, SYNC a Pictures/Remio y solicitud de indexación multimedia |
| Copia y restauración ZIP | Manifiesto formato 1, APK base/splits, siete ajustes básicos, selección todas/ninguna, copias solo de ajustes, validación previa de paquetes/SDK y resumen parcial |
| Actualizaciones OTA | Los mismos dos paquetes compatibles del Android; consulta, bloqueo y reactivación confirmados y verificados |
| Historial | Últimas 100 acciones de herramientas guardadas localmente |

## Diferencias y límites

- iOS no permite extraer APK de aplicaciones instaladas en el iPhone. Los lotes se crean importando APK desde Archivos.
- No se ha implementado USB OTG ni activar ADB desde USB en iOS. En el Portal actual se utiliza ADB por Wi-Fi ya habilitado. El selector común incluye búsqueda ADB manual en hasta 253 direcciones del segmento /24 de la Wi-Fi, limitada además por la máscara real. Usa grupos de 12 conexiones, timeout de un segundo y cancelación. No envía claves, no abre shell y no se ejecuta automáticamente. Un resultado solo identifica un servicio ADB; el equipo se valida como Portal al usar Herramientas.
- Los nombres de destinos solo cambian en Remio. Una conexión ADB activa a la vez. No se revoca la clave global al olvidar un destino.
- Las copias no incluyen datos privados de apps, cuentas ni fotos. El ZIP y los archivos se limitan a 256 MB. La restauración exige mismo modelo y SDK, y los ajustes están desactivados por defecto.
- El ZIP usa STORE al exportar y acepta STORE/DEFLATE al importar. Se comprueban rutas, duplicados, tamaños y CRC. No acepta cifrado, ZIP64 ni archivos de varios volúmenes. No se extraen rutas a disco al importar.
- Se inspecciona AndroidManifest.xml en ZIP STORE/DEFLATE y XML binario UTF-8/UTF-16. Se valida paquete, SDK mínimo, bounds y CRC; el manifiesto se limita a 4 MB, las cadenas individuales a 64 KB y el total decodificado a 8 MB. La firma y las demás condiciones finales las valida Android. Los lotes contienen APK base independientes; los splits se restauran únicamente desde una copia completa. Antes de escribir se comprueban todos los componentes y su paquete declarado. No se aceptan manifiestos XML de texto ni valores SDK de versiones preliminares o referencias no resolubles.
- La restauración continúa tras fallos individuales y se detiene tras tres consecutivos o al perder ADB. Presenta instaladas, fallos, omitidas y ajustes aplicados. Si falla alguna app, no aplica ajustes. Los lotes se detienen al primer fallo e indican cuántas apps se instalaron. No se eliminan apps instaladas para simular rollback.

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

## Revisión de mejoras de octubre de 2026

Se ha comprobado el lector con el APK oficial PortalToolkit-v1.1.0-debug.apk, sin instalarlo: paquete com.portalinstaller, minSDK 26 y versión 1.1.0. Las pruebas incluyen STORE/DEFLATE, UTF-8/UTF-16, SDK incompatible, paquete falso, truncación, CRC, cifrado y offsets inválidos. La búsqueda ADB se prueba mediante sus límites de dirección/máscara; su ejecución real sobre la red completa queda para una prueba manual.

El aviso central de envío se ha revisado en el simulador y se ha cancelado sin enviar archivos. Las miniaturas usan ImageIO con downsampling y un límite de 32 MB para la vista previa; una imagen mayor puede mostrar un marcador en lugar de miniatura. El límite de transferencia sigue siendo 256 MB. En un envío parcial se retiran los elementos completados y se conserva lo pendiente.

No se han probado instalaciones, restauraciones ni cambios OTA en el Portal del propietario durante esta revisión. La prueba de release debe usar archivos elegidos por él. Las funciones USB y extraer APK de apps del iPhone no se han añadido: requieren capacidades específicas de Android y no se simulan como si estuviesen disponibles en iOS.
