# Releases y carga lateral

## Un IPA y una fuente

`Remio.ipa` contiene la app arm64 para iOS/iPadOS 26. Es el mismo archivo para AltStore Classic, SideStore y LiveContainer. La fuente `distribution/source.json` usa el formato AltSource. No se generan variantes con metadatos divergentes ni se confunde este flujo con notarización PAL.

URL pública prevista:

```
https://raw.githubusercontent.com/AnubisReal/Remio/main/distribution/source.json
```

Mientras no haya una release publicada, `apps` permanece vacío: no se anuncian descargas inexistentes. El primer borrador lleva versión 0.1.0, build 1.

## Compilación local

```bash
REMIO_VERSION=0.1.0 REMIO_BUILD_NUMBER=1 bash scripts/build-sideload-ipa.sh
```

Produce `dist/Remio.ipa` y `dist/Remio.ipa.sha256`. No necesita certificado ni Apple ID. El script crea un archive Release de dispositivo, copia únicamente la app a `Payload/Remio.app`, excluye perfiles de desarrollo, valida el Mach-O arm64/plataforma y comprueba el ZIP. El instalador debe firmarlo después; esta compilación no sirve para ejecutar un simulador.

Se revisó el flujo local `Scripts/build-sideload-ipa.sh` de Swiftfin como referencia. El script de Remio se ha escrito para este proyecto y no copia su configuración de firma ni su identidad.

## Publicar desde GitHub

1. Incorporar a `main` los cambios revisados y actualizar `docs/RELEASE-NOTES.md`.
2. Ejecutar **Actions → Build sideload release** con versión `X.Y.Z` y un número de compilación creciente. Solo versiones numéricas estables; los tags son `vX.Y.Z`.
3. El workflow ejecuta las pruebas, construye el IPA y crea un **borrador** con IPA y SHA-256. No publica automáticamente.
4. Descargar ese IPA y comprobar instalación, Keychain, vinculación/reconexión, Archivos/Fotos y controles en un iPhone real. Repetir dentro de LiveContainer antes de afirmar compatibilidad completa. No probar instalaciones, OTA o restauraciones en el Portal sin archivos y alcance elegidos.
5. Publicar el borrador desde GitHub. El evento `release.published` ejecuta **Update app source**. Las prereleases no se incorporan al canal estable.
6. El generador descarga el IPA publicado, obtiene versión/build/iOS mínimo/permisos/tamaño reales, conserva versiones anteriores y actualiza `distribution/source.json` en `main`.

El token automático de Actions necesita escritura de contenido. No se almacenan certificados ni credenciales Apple en GitHub. Si se activa protección de `main` que impida commits de Actions, habrá que permitir ese flujo o enviar la actualización por PR.

Los lanzamientos se serializan. No volver a publicar un tag existente con otro IPA: usar nueva versión y build. El número de build del workflow debe incrementarse aunque la versión del proyecto Xcode siga siendo la de desarrollo.

## Actualización manual de la fuente

Solo después de publicar el IPA:

```bash
python3 scripts/update-source.py --ipa dist/Remio.ipa \
  --repository AnubisReal/Remio --tag v0.1.0 --notes docs/RELEASE-NOTES.md
```

Revisar y subir el JSON. La URL de descarga fija el tag; no apunta a `latest`, para que tamaño y versión siempre correspondan al mismo archivo. No se incluyen `marketplaceID`, certificados ni permisos no utilizados.

## Limpieza del repositorio

Las referencias Android, las notas históricas, capturas y los experimentos sobre Immortal quedan en `references/`, ignorado. Se conserva el historial original solo en ramas locales y el remoto de referencia, separado del historial nuevo de Remio. No ejecutar `git push --all` ni `git push --tags` hacia el repositorio de Remio: únicamente se publica su rama nueva y sus futuros tags.

`.gitignore` excluye también artefactos, perfiles, claves y ajustes personales de Xcode. Esto no reemplaza revisar `git diff --cached` antes de publicar. Las credenciales reales viven en Keychain, nunca en la fuente de aplicaciones.

## Referencias oficiales

- [Formato de fuentes de AltStore](https://faq.altstore.io/developers/make-a-source)
- [Compatibilidad de fuentes en SideStore](https://docs.sidestore.io/docs/advanced/app-sources)
- [Fuentes en LiveContainer](https://livecontainer.github.io/en/docs/guides/sources)
