# Localización nativa: español e inglés

Remio usa los catálogos de cadenas de Xcode. El idioma de desarrollo sigue siendo español (`es`), con traducción completa a inglés genérico (`en`). iOS elige el idioma compatible según las preferencias del usuario, incluido el idioma por app cuando esté disponible. Si no hay coincidencia, el idioma de desarrollo es el respaldo. No se modifica `AppleLanguages` desde la app ni se fuerza un idioma en producción.

## Recursos

- `ios/Remio/Resources/Localizable.xcstrings`: interfaz, errores propios, progreso y accesibilidad.
- `ios/Remio/Resources/InfoPlist.xcstrings`: descripción del permiso de red local.
- `SWIFT_EMIT_LOC_STRINGS = YES` en Debug y Release: Xcode extrae las cadenas marcadas durante la compilación.

Las cadenas creadas en modelos y pasadas como `String` a componentes usan `String(localized:)`. Los literales nativos de SwiftUI también se extraen. Los identificadores de navegación, claves de preferencias, protocolo, comandos ADB y nombres de paquetes permanecen estables y no se traducen. Los nombres de apps, dispositivos, lotes, contenido multimedia y respuestas técnicas del equipo son datos externos y conservan su valor original.

Los textos con cantidades usan interpolación y variantes nativas de plural en el catálogo. Fechas, tamaños y tiempos siguen utilizando los formateadores de Foundation o SwiftUI. Los nombres de las herramientas ya no dependen del `rawValue` del enum de navegación.

El historial persiste identificadores de operación y argumentos, y traduce sus títulos al mostrarlos. Las descripciones antiguas conocidas en español se interpretan sin cambiar nombres de paquetes o lotes; las entradas desconocidas se conservan literalmente. Los cambios de idioma se aplican al volver a iniciar Remio; no hay un selector de idioma propio ni cambios en las credenciales de mando/ADB.

## Mantener las traducciones

1. Crear textos visibles con APIs de localización de Apple. Añadir contexto para mensajes ambiguos.
2. Compilar en Xcode y revisar las cadenas nuevas o pendientes del catálogo.
3. Completar español e inglés, conservando los argumentos interpolados y revisando plurales.
4. Ejecutar `python3 -m unittest discover -s tests/distribution -v` y `swift test`.
5. En el esquema, probar Application Language en inglés y español, y pseudolenguajes para detectar recortes.

## Comprobación en simulador

Además de revisar la interfaz visualmente, el modo DEBUG del simulador acepta `--localization-self-test`. Comprueba los recursos `es.lproj` y `en.lproj`, las variantes de uno/dos elementos y el texto de permiso, y escribe el resultado en `Documents/localization-self-test.json`. No modifica el Portal. Los monitores normales de conexión siguen ejecutándose.

Ejemplo con un simulador arrancado y la app instalada:

```bash
xcrun simctl launch booted com.remio.app --localization-self-test -AppleLanguages '(en)' -AppleLocale en_US
```

Los argumentos son solo de prueba. Terminar la app y lanzarla normalmente restaura la selección habitual del sistema. `REMIO_SETTINGS_PREVIEW=1` abre Ajustes en DEBUG para revisar las traducciones sin navegar manualmente.

## Fuentes oficiales de Apple

- [String Catalogs](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)
- [Preparar textos para traducir](https://developer.apple.com/documentation/xcode/preparing-your-apps-text-for-translation)
- [Preparar vistas SwiftUI](https://developer.apple.com/documentation/swiftui/preparing-views-for-localization)
- [Cómo iOS elige el idioma](https://developer.apple.com/library/archive/qa/qa1828/_index.html)
- [Localizar los avisos de permisos](https://developer.apple.com/documentation/uikit/requesting-access-to-protected-resources)
- [Probar localizaciones](https://help.apple.com/xcode/mac/current/en.lproj/dev499a9529e.html)
