# Gabi 🐾

Mascota virtual de escritorio nativa para macOS hecha en Swift + AppKit en memoria de **Gabi**.

## Características
- **Ultraligera (~0,1% CPU en reposo, ~56 MB RAM)**: renderizado *pixel art* acelerado por GPU (`CALayer` + `CGImage`) y FPS adaptativos.
- **Siempre contigo**: flota sobre tus ventanas y te acompaña en todos tus escritorios (*Spaces*) desde la barra de menú (`🐾`).
- **Animaciones pixel art**: pasear, correr, saltar, sentarse, ladrar, acariciar con corazones ♥, tumbarse y dormir (`zZz`).
- **Ladrido real de Gabi** integrado (`assets/sounds/gabi_bark.wav`), con opción de cambiar o silenciar el audio desde el menú.
- **Pelota de tenis (`🎾 Lanzar pelota`)**: física de rebote y Gabi corre a atraparla.
- **Modo quieto / esquina**: `💤 Quedarse acostado` o `↘️ Ir a la esquina` para que te acompañe sin molestar.
- **Control por voz (`⌥G` / Option+G)** con reconocimiento nativo en español (`Speech.framework`):
  - *"Gabi, abre YouTube"* / *"Gabi, busca [algo] en Google"* (Gabi corre hacia la barra y teclea en el navegador si le das permiso de Accesibilidad).
  - *"Gabi, túmbate"* / *"levántate"* / *"a la esquina"* / *"pelota"* / *"salta"* / *"guapo"* / *"ladra"*.
- **Órdenes personalizadas (`commands.json`)**: edítalas desde **`📝 Editar órdenes personalizadas...`** (se recargan al instante sin reiniciar).
- **IA opcional (Gemini)**: configura tu API Key gratuita desde **`🧠 Configurar IA (Gemini)...`** para hacerle preguntas rápidas a Gabi.

## Compilar y ejecutar (macOS)
```bash
./build.sh
open Gabi.app
```

## Generar instalador `.dmg` para compartir / GitHub Releases
```bash
./scripts/package_dmg.sh
```

## Abrir automáticamente al encender el Mac
1. **Ajustes del Sistema → General → Ítems de inicio de sesión**.
2. Pulsa **+** y selecciona `Gabi.app` (puedes moverla a `/Applications`).
