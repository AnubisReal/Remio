# Identidad Remio

**Pulse** es la identidad principal elegida. **Signal** se conserva como alternativa seleccionable en Ajustes. Orbit queda archivado como concepto, sin incluirse en la app.

Cada carpeta `pulse/` y `signal/` contiene:

- `logo.svg`: símbolo vectorial con transparencia, sin nombre ni maqueta. ViewBox 1024 × 1024.
- `logo.png`: símbolo transparente de 1024 × 1024.
- `app-icon.svg`: composición vectorial con fondo cuadrado completo.
- `app-icon.png`: icono opaco de 1024 × 1024, sin esquinas recortadas; iOS aplica su propia máscara.

Los SVG son reconstrucciones geométricas limpias de los conceptos, no imágenes incrustadas ni calcos exactos del bitmap. El hueco de Pulse usa máscara vectorial para conservar transparencia. Paleta Pulse actual: fondo carbón `#121212`, símbolo gris claro `#D4D4D4`. Interfaz neutra con superficies grafito `#242424`; sin verde, degradados ni resplandores. Signal: fondo `#101114`, símbolo `#FFFFFF`.

`concepts/` conserva las tres láminas iniciales con sus nombres originales. No usar esas láminas como iconos finales.

`scripts/export_identity.py` contiene la geometría fuente y regenera SVG, PNG supersampleados y recursos de Xcode. Requiere Python 3 y Pillow. Cambiar la geometría allí y regenerar para mantener sincronizados los recursos. Los SVG también son editables en herramientas vectoriales; trasladar sus cambios al exportador antes de volver a ejecutarlo.
