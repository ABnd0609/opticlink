# OpticLink: Sistema de Cámara Profesional iOS -> Linux

**OpticLink** convierte tu iPhone en una cámara web secundaria de calidad profesional para Linux con control granular en tiempo real de enfoque manual, exposición, ISO, balance de blancos, zoom y lentes ópticos, inyectando el video directamente en `/dev/video0` (`v4l2loopback`).

---

## Estructura del Proyecto

* **`linux/`**: Cliente de escritorio moderno escrito en Python 3 con **GTK4 / Libadwaita** y aceleración por **GStreamer**, diseñado para integrarse nativamente con GNOME en Bazzite/Fedora.
* **`ios/`**: Aplicación nativa en **Swift + SwiftUI** utilizando `AVFoundation` para control milimétrico del sensor y `VideoToolbox` para compresión H.264 por hardware con latencia inferior a 30 ms.
* **`.github/workflows/`**: Pipeline de **GitHub Actions** para compilar la app de iOS en la nube de macOS y generar el archivo `.ipa` instalable sin necesidad de tener una Mac física.
* **`docs/`**: Informes de las rondas de auditoría adversarial, arquitectura del sistema y guía detallada de sideloading.

---

## Requisitos en Linux

* **Bazzite / Fedora / Ubuntu** con soporte para `v4l2loopback` (preinstalado en Bazzite en `/dev/video0`).
* Bibliotecas del sistema (disponibles nativamente):
  * `python3-gobject` (PyGObject)
  * `gtk4` y `libadwaita-1`
  * `gstreamer1.0` y plugins base/good (`v4l2sink`)
  * `usbmuxd` (para conexión por cable USB Lightning / USB-C)

---

## Cómo Ejecutar el Panel de Control en Linux

```bash
cd linux
python3 app.py
```

---

## Conexión

1. **Por Cable USB (Recomendado para máxima estabilidad):**
   * Conecta el iPhone a la laptop con su cable USB.
   * Toca "Confiar en esta computadora" en el iPhone si aparece el aviso.
   * La app en Linux detecta automáticamente el túnel USB mediante `usbmuxd`.
2. **Por Wi-Fi:**
   * Conecta ambos dispositivos a la misma red local.
   * Ingresa la dirección IP que muestra la pantalla del iPhone en el panel de control de Linux y pulsa **Conectar**.
