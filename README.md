<p align="center"><img src="design/identity/pulse/logo.png" width="76" alt="Remio"></p>
<h1 align="center">Remio</h1>
<p align="center">Un mando nativo de iOS para tu Portal.</p>

Remio reúne control remoto y herramientas de administración de Meta/Facebook Portal en una app SwiftUI. Requiere **iOS/iPadOS 26**, un Portal con el mando de **Immortal** operativo y ambos equipos en la misma red local. El equipo de referencia es Portal+ 2021; otros modelos necesitan validación.

### Qué incluye

- Trackpad, clic, Atrás, Inicio, Recientes y desplazamiento.
- Teclado nativo integrado en la pantalla del mando.
- Aplicaciones con sus iconos, apertura y controles multimedia con carátula y búsqueda temporal cuando el Portal facilita esos datos.
- ADB por Wi-Fi: gestión de APK, lotes, envío de imágenes desde Fotos o Archivos, copias, información del equipo y control de componentes OTA compatibles.
- Reconexión de sesiones guardadas y credenciales en el llavero del dispositivo.
- Iconos Pulse y Signal. Mando direccional opcional mediante ADB, desactivado por defecto.

### Instalar

El IPA se distribuirá en [Releases](https://github.com/AnubisReal/Remio/releases). La primera versión se prepara como borrador hasta probarla en un dispositivo real.

Fuente compartida para **AltStore Classic, SideStore y LiveContainer**:

```text
https://raw.githubusercontent.com/AnubisReal/Remio/main/distribution/source.json
```

La fuente solo incluye versiones publicadas. AltStore y SideStore vuelven a firmar el IPA con la identidad del usuario; el archivo no es una distribución de App Store ni de AltStore PAL. LiveContainer instala el mismo IPA, pero su funcionamiento con el llavero, red local e iconos alternativos debe comprobarse dentro de ese contenedor.

### Desarrollar y compilar

Abrir `ios/Remio.xcodeproj` con **Xcode 26 o posterior** y seleccionar el esquema **Remio**. Swift 6 y concurrencia estricta, sin dependencias externas. Para instalar directamente desde Xcode en un iPhone, configurar un equipo de firma propio.

```bash
# Pruebas sin modificar ningún Portal
swift test
python3 -m unittest discover -s tests/distribution -v

# Simulador: conserva la firma necesaria para Keychain
bash scripts/run_simulator.sh

# IPA arm64 Release para carga lateral
bash scripts/build-sideload-ipa.sh
```

El IPA y su SHA-256 se generan en `dist/`, excluido de Git. Las compilaciones para simulador mantienen su firma; el IPA para carga lateral se prepara sin certificados personales para que lo firme el instalador.

### Estructura

| Carpeta | Contenido |
|---|---|
| `ios/` | App, proyecto Xcode y configuración |
| `design/` | Identidades vectoriales, PNG y marcas sociales |
| `docs/` | Conexiones, límites, distribución y notas de versión |
| `scripts/` | Compilación, validación y generación de la fuente |
| `distribution/` | Fuente pública de aplicaciones |
| `tests/` | Regresiones de protocolo y distribución |
| `references/` | Referencias locales ignoradas; no se publican |

### Conexión y límites

El mando requiere una primera vinculación por PIN desde la pantalla QR del Portal. ADB tiene su propia autorización inicial, que debe aceptarse en el equipo; después Remio intenta reconectar con la misma clave. No se evita ninguna autorización del Portal y no se activa ADB automáticamente.

El mando usa HTTP local y ADB clásico TCP, sin cifrado de transporte: utiliza una red de confianza. La detección automática del teclado puede vaciar el campo remoto antes de abrirse, tal como indica su ajuste. Las operaciones que instalan, eliminan o restauran requieren confirmación. La app no cambia el firmware ni instala Immortal automáticamente.

Las herramientas de escritura están implementadas, pero su validación completa en hardware sigue pendiente. Las copias contienen APK y determinados ajustes, no cuentas ni datos privados de aplicaciones. Consulta [los límites de las herramientas](docs/TOOLKIT-PARITY.md), [las conexiones](docs/DUAL-CONNECTION.md) y [cómo publicar versiones](docs/DISTRIBUTION.md).

### Créditos

Creado por [AnubisReal](https://github.com/AnubisReal) · [Instagram](https://www.instagram.com/anubisreal/) · [X](https://x.com/Anubisreal23).

[Portal Toolkit](https://github.com/jurax-sys/portal-toolkit) es la referencia funcional de las herramientas Android. [Immortal](https://github.com/starbrightlab/immortal) proporciona el servicio remoto del Portal. El código Android y los experimentos sobre Immortal permanecen fuera de la distribución de Remio. Remio es un proyecto independiente, sin afiliación con Meta.
