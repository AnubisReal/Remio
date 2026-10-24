# Remio 0.1.3

- Aviso central nativo con Enviar y Cancelar antes de transferir imágenes.
- Miniaturas de imágenes seleccionadas desde Fototeca o Archivos y comprobación de formato antes de enviarlas. Un envío parcial conserva únicamente los elementos pendientes.
- Copias solo de ajustes, botones Seleccionar todas/Ninguna y fecha/SDK en la vista previa.
- Validación de AndroidManifest.xml antes de transferir APK: paquete, Android mínimo, ZIP/CRC y componentes de copias. Los lotes se comprueban completos antes de instalar el primer APK.
- Errores de instalación más claros para firma incompatible, versiones antiguas, Android o arquitectura incompatibles y espacio insuficiente.
- Restauración con resumen de instaladas, fallos, omitidas y ajustes. Se detiene tras tres fallos consecutivos o al perder ADB; si alguna app falla, no se aplican ajustes.
- Versión y tamaño en la lista de apps, con orden opcional por tamaño.
- Búsqueda ADB manual y cancelable en el segmento Wi-Fi: máximo 253 direcciones y sin envío de claves durante el escaneo. Seleccionar un resultado inicia la conexión y autorización habitual.
- Textos nuevos disponibles en español e inglés.

Revisión: pruebas automatizadas de manifiestos binarios UTF-8/UTF-16, STORE/DEFLATE, SDK, paquete, CRC, cifrado y archivos dañados; lector comprobado con el APK oficial de Portal Toolkit sin instalarlo. Aviso central y miniaturas revisados en el simulador. Las transferencias, instalaciones y restauraciones nuevas requieren pruebas controladas en el Portal con archivos elegidos por el propietario; no se han ejecutado sobre su equipo durante esta revisión. USB y extracción de APK de apps instaladas en el iPhone no están implementados.

Requiere iOS/iPadOS 26 o posterior. IPA para carga lateral con AltStore Classic, SideStore o LiveContainer. ADB debe estar habilitado y autorizado; la compatibilidad dentro de LiveContainer depende también de su configuración.
