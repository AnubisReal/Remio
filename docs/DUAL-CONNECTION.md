# Conexiones del Portal

Mando (HTTP/8723) y administración (ADB/5555 editable) comparten la IP elegida, pero tienen estados y credenciales independientes.

## Mando

RemoteModel, PortalAPI y la credencial Keychain existentes. La autenticación y cola de acciones se conservan.

## ADB

AdministrationModel mantiene una conexión TCP ADB clásica. ADBIdentity genera una clave RSA de 2048 bits con Security.framework y la conserva en el llavero, accesible desbloqueado y sin sincronización a otros dispositivos. La clave privada nunca se exporta. El formato público de Android incluye módulo, exponente y constantes Montgomery; no son material privado.

Flujo: CNXN → AUTH/TOKEN → AUTH/SIGNATURE. Si no se reconoce la firma: nuevo TOKEN → AUTH/RSAPUBLICKEY (Remio@iOS). El usuario acepta en la pantalla del Portal. Solo al recibir CNXN válido con banner device:: y payload completo pasa a conectado. La sesión permanece abierta al cerrar la hoja; se cancela al pasar la app a segundo plano. Una nueva conexión usa la misma clave.

No se instala ni habilita nada en el Portal. La aceptación puede guardar la clave pública de Remio entre los clientes ADB autorizados. La autenticación por sí sola no abre shell ni ejecuta comandos. La pestaña Herramientas usa streams explícitos para consultas, transferencias y operaciones confirmadas; ver TOOLKIT-PARITY.md. No activa ni reconfigura el servicio ADB.

Límites: IP privada literal, puerto acotado, sin tráfico celular, cabeceras de 24 bytes, payload máximo 4096 bytes, checksum clásico validado, cancelación por UUID, ocho segundos de conexión inicial y 90 segundos para aceptación manual. Solo se envía una firma y una clave pública por intento. No se usa la clave del Mac ni se reutiliza el token HTTP. TLS/depuración inalámbrica de Android 11+ no está implementado.

Validación local: formato de cabeceras, tamaños, magic, clave pública contra vector matemático conocido, firma/verificación del desafío con Security.framework y regresiones del mando. La aprobación real en el Portal y la reconexión con su clave aceptada deben verificarse con el propietario.

Referencias:
- https://android.googlesource.com/platform/system/adb/+/abe7b89be678981508f4bce18035054b35f703f7/protocol.txt
- https://developer.apple.com/documentation/security/seckeycreatesignature(_:_:_:_:)

## Reconexión automática

El destino ADB se guarda localmente como IP y puerto validados (sin claves en preferencias). La app supervisa ADB desde su raíz mientras está en primer plano, sin depender de las pestañas. Reintenta pérdidas de conexión con esperas crecientes de 3 a 30 segundos. Al volver del segundo plano usa la misma clave del llavero. Si la firma deja de ser reconocida, detiene la reconexión automática y solicita conectar manualmente: nunca envía claves públicas nuevas en un bucle automático. La versión previa sin destino guardado migra la IP del mando y puerto 5555 únicamente si ya existe una identidad ADB local.

Referencia Android: MainScreen.kt ejecuta viewModel.connect al arrancar si hay una IP guardada. SavedPortalStore y preferencias conservan destinos; AdbKeyPairProvider conserva la identidad RSA. Remio añade también reintentos de pérdida y recuperación en primer plano.
