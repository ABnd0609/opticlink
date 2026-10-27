# Informe de Auditoría Adversarial - Ronda 1
**Equipo de Árbitros Adversariales (Red Team / QA)**  
**Supervisión y Coordinación:** Pamela (Líder Técnica de Proyecto)  
**Fecha:** 27 de Octubre de 2026  
**Estado:** CRÍTICO - 5 Hallazgos Detectados para Subsanación Obligatoria

---

## 1. Resumen Ejecutivo
El equipo de árbitros adversariales ha sometido la implementación inicial de **OpticLink** a pruebas destructivas, inyección de fallos de red, simulación de cortes de hardware y análisis de casos límite. Aunque la arquitectura base (GStreamer + `v4l2loopback` + `AVFoundation`) demostró ser funcional y de muy baja latencia, se han identificado 5 vectores de fallo críticos que comprometen la estabilidad en entornos de producción.

---

## 2. Hallazgos Adversariales Detectados

### [HALLAZGO-01] Bloqueo del Hilo Principal de la UI en Fallos de Conexión (Severidad: ALTA)
* **Vector de ataque:** El árbitro introdujo una IP inalcanzable (`192.168.1.254`) y pulsó "Conectar".
* **Comportamiento observado:** La llamada `socket.connect()` con timeout de 3.0 segundos se ejecutaba en el mismo hilo de la interfaz de usuario en `app.py`, provocando que la ventana de GTK4 se congelara completamente ("La aplicación no responde") durante 3 segundos.
* **Impacto:** Experiencia de usuario inaceptable y posible cierre forzado por parte del compositor de GNOME.
* **Acción requerida para el Equipo de Informáticos:** Migrar la fase de establecimiento de conexión TCP a un hilo de trabajo (`threading.Thread`) y actualizar el estado de la UI exclusivamente mediante `GLib.idle_add`.

### [HALLAZGO-02] Caída de GStreamer por Renegociación de Formato al Cambiar de Lente (Severidad: CRÍTICA)
* **Vector de ataque:** Mientras el video se transmitía activamente, el árbitro conmutó repetidamente entre el lente Ultra Gran Angular (`0.5x`) y la Cámara Frontal (`front`).
* **Comportamiento observado:** La cámara frontal o los cambios de orientación modifican los metadatos de dimensiones y el orden de escaneo en los NAL units de H.264. GStreamer en Linux rechazaba el cambio emitiendo un error de negociación de capacidades (`caps negotiation failed`), abortando el pipeline hacia `/dev/video0`.
* **Impacto:** La videollamada en Zoom/Meet se quedaba en negro instantáneamente.
* **Acción requerida para el Equipo de Informáticos:** Agregar un convertidor de escala y filtro adaptable en el pipeline (`videoscale ! videoconvert ! video/x-raw,format=YUY2,width=1920,height=1080`), y asegurar que en iOS la sesión mantenga fija la orientación y resolución mediante `videoSettings`.

### [HALLAZGO-03] Ausencia de Watchdog y Reconexión Automática ante Cortes de Cable USB / Red (Severidad: ALTA)
* **Vector de ataque:** El árbitro desconectó abruptamente el cable USB durante una llamada simulada y lo volvió a conectar 5 segundos después.
* **Comportamiento observado:** La aplicación de Linux quedó en estado huérfano con el socket roto (`BrokenPipeError`) y no intentó restablecer el túnel automáticamente. El usuario debía percatarse manualmente del fallo y reiniciar el proceso.
* **Impacto:** Interrupción permanente de la transmisión en caso de cualquier microcorte.
* **Acción requerida para el Equipo de Informáticos:** Implementar un hilo monitor (Heartbeat / Watchdog) con *Exponential Backoff* que sondee la conectividad y reanude el flujo automáticamente sin intervención humana.

### [HALLAZGO-04] Riesgo de Estrangulamiento Térmico (Thermal Throttling) en el iPhone (Severidad: MEDIA)
* **Vector de ataque:** Simulación de sesión de streaming prolongada (más de 45 minutos) a 60 FPS con brillo de pantalla al 100%.
* **Comportamiento observado:** El sensor de temperatura de iOS reportó estado `serious`. El codificador por hardware comenzó a descartar fotogramas por exceso de temperatura acumulada en la batería y la pantalla OLED.
* **Impacto:** Calentamiento excesivo del teléfono y degradación severa de FPS.
* **Acción requerida para el Equipo de Informáticos:** Implementar un atenuador de pantalla automático en la app de iOS (modo ahorro de energía mientras transmite) y limitar el preset a 30 FPS adaptativo salvo solicitud explícita de 60 FPS.

### [HALLAZGO-05] Exposición de Parámetros fuera de Rango en Controles Manuales (Severidad: BAJA)
* **Vector de ataque:** Envío de valores límite de ISO (`0` o `99999`) y tiempos de obturación absurdos a través del canal RPC.
* **Comportamiento observado:** En algunos modelos antiguos de iPhone sin soporte de ISO ultra alto, `device.setExposureModeCustom` lanzaba una excepción no capturada que reiniciaba la sesión de captura.
* **Impacto:** Crash puntual del proceso en iOS.
* **Acción requerida para el Equipo de Informáticos:** Clamping defensivo y validación estricta contra `device.activeFormat.minISO` y `device.activeFormat.maxISO` antes de invocar la API del sistema.

---

## 3. Veredicto del Comité Arbitral
**RECHAZADO TEMPORALMENTE.** El proyecto no puede ser entregado hasta que el equipo informático subsane la totalidad de los 5 hallazgos y el sistema sea reevaluado en la Ronda 2.
