# Remio para iOS

Abrir `Remio.xcodeproj` en Xcode 26 o posterior y seleccionar el esquema Remio. Requiere iOS/iPadOS 26. Para un dispositivo físico, configurar un equipo de firma propio. No hay dependencias externas.

## Conectar

1. Conectar el iPhone y el Portal a la misma red.
2. Abrir el selector de conexión y permitir acceso a la red local.
3. Seleccionar el Portal descubierto o introducir su IP y puerto del mando.
4. Vincular una vez con el PIN de la pantalla QR del Portal. La sesión se conserva en Keychain.
5. Para Herramientas, habilitar previamente ADB TCP en el Portal, conectar a su puerto y aceptar la clave de Remio con «Permitir siempre».

Las sesiones del mando y de ADB son independientes. La reconexión se realiza al volver a primer plano; no se repiten automáticamente operaciones de escritura.

## Teclado

La barra de escritura Liquid Glass permanece en Home, junto al teclado nativo. Las ediciones se envían de forma incremental. La detección automática se comprueba después de un clic y puede vaciar el contenido previo del campo remoto; se indica en Ajustes. Borrar con la barra local vacía no sigue eliminando contenido remoto.

## Compilar

Desde la raíz:

```bash
bash scripts/run_simulator.sh
bash scripts/build-sideload-ipa.sh
```

El primer script mantiene la firma del simulador para que funcione Keychain. El segundo produce un IPA Release para dispositivos arm64, que debe firmar el instalador de carga lateral. No instalar el IPA sin firma directamente con Xcode ni desactivar la firma del simulador.

Documentación: [distribución](../docs/DISTRIBUTION.md), [herramientas](../docs/TOOLKIT-PARITY.md) y [conexiones](../docs/DUAL-CONNECTION.md).
