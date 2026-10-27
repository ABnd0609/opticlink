import gi
gi.require_version("Gst", "1.0")
gi.require_version("GLib", "2.0")
from gi.repository import Gst, GLib
import threading
from typing import Optional, Callable

class VideoReceiver:
    """
    Gestor de pipeline GStreamer para recibir el flujo H.264 por TCP
    e inyectarlo de forma acelerada en el dispositivo de bucle invertido /dev/video0.
    Incluye normalización de escala y formato para tolerancia a cambios de lente en caliente.
    """
    def __init__(self, device: str = "/dev/video0", on_status_change: Optional[Callable[[str], None]] = None):
        self.device = device
        self.on_status_change = on_status_change
        
        Gst.init(None)
        self.pipeline: Optional[Gst.Pipeline] = None
        self._bus = None
        self._is_running = False

    @property
    def is_running(self) -> bool:
        return self._is_running

    def start_network_stream(self, host: str = "127.0.0.1", port: int = 8554) -> bool:
        """
        Inicia la recepción de video en red desde el iPhone y lo proyecta a /dev/video0.
        Blindado con videoscale y caps fijas para evitar caídas por renegociación de lente.
        """
        self.stop()
        
        # Pipeline blindado con normalización de escala (1920x1080 YUY2)
        pipeline_str = (
            f"tcpclientsrc host={host} port={port} ! "
            f"h264parse ! "
            f"avdec_h264 ! "
            f"videoconvert ! "
            f"videoscale ! "
            f"video/x-raw,format=YUY2,width=1920,height=1080 ! "
            f"v4l2sink device={self.device} sync=false"
        )
        
        return self._launch_pipeline(pipeline_str, f"Transmitiendo desde {host}:{port} a {self.device}")

    def start_test_pattern(self) -> bool:
        """
        Inicia un patrón de prueba SMPTE en /dev/video0 para validar que la cámara virtual funciona
        incluso sin tener el iPhone conectado en este instante.
        """
        self.stop()
        pipeline_str = (
            f"videotestsrc pattern=smpte is-live=true ! "
            f"videoconvert ! "
            f"video/x-raw,format=YUY2,width=1280,height=720,framerate=30/1 ! "
            f"v4l2sink device={self.device} sync=false"
        )
        return self._launch_pipeline(pipeline_str, f"Patrón de prueba activo en {self.device}")

    def _launch_pipeline(self, pipeline_str: str, success_msg: str) -> bool:
        try:
            self.pipeline = Gst.parse_launch(pipeline_str)
            self._bus = self.pipeline.get_bus()
            self._bus.add_signal_watch()
            self._bus.connect("message", self._on_bus_message)
            
            ret = self.pipeline.set_state(Gst.State.PLAYING)
            if ret == Gst.StateChangeReturn.FAILURE:
                self.stop()
                if self.on_status_change:
                    self.on_status_change(f"Error: Falló el inicio del pipeline GStreamer en {self.device}")
                return False
                
            self._is_running = True
            if self.on_status_change:
                self.on_status_change(success_msg)
            return True
        except Exception as e:
            self.stop()
            if self.on_status_change:
                self.on_status_change(f"Excepción al crear pipeline: {e}")
            return False

    def _on_bus_message(self, bus, message):
        t = message.type
        if t == Gst.MessageType.ERROR:
            err, debug = message.parse_error()
            self.stop()
            if self.on_status_change:
                self.on_status_change(f"Error de GStreamer: {err.message}")
        elif t == Gst.MessageType.EOS:
            self.stop()
            if self.on_status_change:
                self.on_status_change("Transmisión finalizada (EOS)")

    def stop(self):
        if self.pipeline:
            self.pipeline.set_state(Gst.State.NULL)
            self.pipeline = None
            self._bus = None
        self._is_running = False
