# Arquitectura del Sistema OpticLink

## 1. Visión General y Objetivos de Diseño

El sistema OpticLink está diseñado con cuatro pilares fundamentales:
1. **Latencia ultra baja (<40ms)**: Streaming de video en tiempo real adecuado para videollamadas, streaming en vivo y monitorización sin desincronización perceptible.
2. **Control milimétrico del sensor**: Acceso irrestricto desde Linux a los parámetros de hardware de la cámara del iPhone (Enfoque manual, ISO, tiempo de obturación, balance de blancos, selección de lentes, zoom y flash).
3. **Mínimo consumo de recursos en Linux**: Inyección directa en el kernel mediante `v4l2loopback` (`/dev/video0`) usando pipelines acelerados de GStreamer con cero transcodificación innecesaria.
4. **Resiliencia en transporte dual**: Soporte transparente tanto para Wi-Fi (LAN) como para cable USB (multiplexación nativa con `usbmuxd`).

---

## 2. Diagrama de Arquitectura

```
┌─────────────────────────────────────────────────────────────┐
│                        iPhone (iOS)                         │
│                                                             │
│   ┌─────────────────────┐       ┌──────────────────────┐    │
│   │  AVCaptureSession   │◄─────►│    CameraManager     │    │
│   │ (4K/1080p 60/30fps) │       │ (ISO, Focus, Lenses) │    │
│   └──────────┬──────────┘       └──────────▲───────────┘    │
│              │ (Raw Frames)                │                │
│              ▼                             │                │
│   ┌─────────────────────┐                  │                │
│   │    VideoToolbox     │                  │ (JSON RPC)     │
│   │   Hardware H.264    │                  │                │
│   └──────────┬──────────┘                  │                │
│              │ (NAL Units)                 │                │
│              ▼                             │                │
│   ┌─────────────────────┐       ┌──────────┴───────────┐    │
│   │ Video Stream Server │       │ Control Server (RPC) │    │
│   │     (Port 8554)     │       │     (Port 8555)      │    │
│   └──────────┬──────────┘       └──────────▲───────────┘    │
└──────────────┼─────────────────────────────┼────────────────┘
               │ (Stream H.264 / TCP)        │ (JSON Socket)
         Cable USB (usbmuxd) / Red Wi-Fi Local
               │                             │
┌──────────────┼─────────────────────────────┼────────────────┐
│              ▼                             ▼                │
│   ┌─────────────────────┐       ┌──────────────────────┐    │
│   │   VideoReceiver     │       │   CameraController   │    │
│   │ (GStreamer Pipeline)│       │      (RPC Client)    │    │
│   └──────────┬──────────┘       └──────────▲───────────┘    │
│              │                             │                │
│              ▼                             │                │
│   ┌─────────────────────┐       ┌──────────┴───────────┐    │
│   │     v4l2sink        │       │   GTK4 / Libadwaita  │    │
│   │   (/dev/video0)     │       │     Interfaz UI      │    │
│   └──────────┬──────────┘       └──────────────────────┘    │
│              │                                              │
│              ▼                                              │
│   [Zoom / Meet / Discord / Apps de Linux]                   │
│                                                             │
│                        Laptop (Linux)                       │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Protocolo de Control (JSON-RPC)

El canal de control opera sobre un socket TCP bidireccional en el puerto `8555` (o reenviado vía `usbmuxd`).
Cada mensaje es un objeto JSON delimitado por un salto de línea (`\n`).

### 3.1. Mensajes del Cliente (Linux -> iOS)

#### Establecer Enfoque Manual
```json
{
  "type": "set_parameter",
  "id": 1,
  "parameter": "focus",
  "mode": "manual",
  "value": 0.65
}
```
*(Valor: flotante entre `0.0` [enfoque macro/cercano] y `1.0` [infinito])*.

#### Establecer Auto-Enfoque Continuo
```json
{
  "type": "set_parameter",
  "id": 2,
  "parameter": "focus",
  "mode": "continuous_auto"
}
```

#### Establecer Exposición Manual (ISO y Shutter)
```json
{
  "type": "set_parameter",
  "id": 3,
  "parameter": "exposure",
  "mode": "manual",
  "iso": 200,
  "duration_seconds": 0.016666
}
```

#### Establecer Balance de Blancos Manual (Temperatura Kelvin)
```json
{
  "type": "set_parameter",
  "id": 4,
  "parameter": "white_balance",
  "mode": "manual",
  "temperature_kelvin": 5500,
  "tint": 0.0
}
```

#### Cambiar de Lente Físico
```json
{
  "type": "set_parameter",
  "id": 5,
  "parameter": "lens",
  "lens": "ultra_wide" 
}
```
*(Opciones: `"ultra_wide"`, `"wide"`, `"telephoto"`, `"front"`)*.

#### Linterna / Antorcha de Relleno
```json
{
  "type": "set_parameter",
  "id": 6,
  "parameter": "torch",
  "level": 0.75
}
```

---

## 4. Pipeline de Video en Linux

El receptor de Linux utiliza la infraestructura nativa de **GStreamer**:

```
tcpclientsrc host={IP} port=8554 
  ! h264parse 
  ! avdec_h264 
  ! videoconvert 
  ! video/x-raw,format=YUY2 
  ! v4l2sink device=/dev/video0 sync=false
```

* `sync=false`: Evita que GStreamer intente sincronizar con relojes del sistema externos, reduciendo la latencia de buffering al mínimo absoluto.
* `video/x-raw,format=YUY2`: Es el formato estándar unificado compatible con la totalidad de aplicaciones de Linux (Firefox, Brave, Chrome, Discord, Zoom, OBS y GNOME Snapshot).
