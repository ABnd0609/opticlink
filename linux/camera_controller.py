import socket
import json
import threading
import time
from typing import Optional, Callable

class CameraController:
    """
    Cliente RPC para comunicación bidireccional con el servidor de control en iOS.
    Soporta auto-reconexión automática con watchdog, envío asíncrono y manejo robusto de excepciones.
    """
    def __init__(self, host: str = "127.0.0.1", port: int = 8555, on_state_change: Optional[Callable[[bool, str], None]] = None):
        self.host = host
        self.port = port
        self.on_state_change = on_state_change
        
        self._socket: Optional[socket.socket] = None
        self._lock = threading.Lock()
        self._connected = False
        self._request_counter = 0
        
        # Watchdog de auto-reconexión
        self._auto_reconnect_enabled = False
        self._watchdog_thread: Optional[threading.Thread] = None

    @property
    def is_connected(self) -> bool:
        return self._connected

    def connect(self, host: Optional[str] = None, port: Optional[int] = None) -> bool:
        if host:
            self.host = host
        if port:
            self.port = port
            
        with self._lock:
            self._close_socket()
            try:
                s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                s.settimeout(3.0)
                s.connect((self.host, self.port))
                s.settimeout(None)
                self._socket = s
                self._connected = True
                if self.on_state_change:
                    self.on_state_change(True, f"Conectado a {self.host}:{self.port}")
                return True
            except Exception as e:
                self._connected = False
                if self.on_state_change:
                    self.on_state_change(False, f"Error al conectar: {e}")
                return False

    def start_watchdog(self):
        """
        Inicia el watchdog en segundo plano para auto-reconexión continua ante caídas de red.
        """
        self._auto_reconnect_enabled = True
        if self._watchdog_thread is None or not self._watchdog_thread.is_alive():
            self._watchdog_thread = threading.Thread(target=self._watchdog_loop, daemon=True)
            self._watchdog_thread.start()

    def stop_watchdog(self):
        self._auto_reconnect_enabled = False

    def _watchdog_loop(self):
        backoff = 2.0
        while self._auto_reconnect_enabled:
            time.sleep(backoff)
            if self._auto_reconnect_enabled and not self._connected:
                success = self.connect()
                if success:
                    backoff = 2.0
                else:
                    backoff = min(10.0, backoff * 1.5)

    def disconnect(self):
        self.stop_watchdog()
        with self._lock:
            self._close_socket()
            self._connected = False
            if self.on_state_change:
                self.on_state_change(False, "Desconectado")

    def _close_socket(self):
        if self._socket:
            try:
                self._socket.shutdown(socket.SHUT_RDWR)
                self._socket.close()
            except Exception:
                pass
            self._socket = None

    def _send_command(self, payload: dict) -> bool:
        with self._lock:
            if not self._connected or not self._socket:
                return False
            
            try:
                self._request_counter += 1
                payload["id"] = self._request_counter
                data = (json.dumps(payload) + "\n").encode("utf-8")
                self._socket.sendall(data)
                return True
            except (socket.error, BrokenPipeError, ConnectionResetError) as e:
                self._connected = False
                self._close_socket()
                if self.on_state_change:
                    self.on_state_change(False, f"Conexión perdida: {e}")
                return False

    # --- Métodos de control granular defensivos ---

    def set_focus(self, mode: str = "continuous_auto", value: float = 0.5):
        cmd = {
            "type": "set_parameter",
            "parameter": "focus",
            "mode": mode,
            "value": max(0.0, min(1.0, float(value)))
        }
        return self._send_command(cmd)

    def set_exposure(self, mode: str = "continuous_auto", iso: Optional[float] = None, duration_seconds: Optional[float] = None):
        cmd = {
            "type": "set_parameter",
            "parameter": "exposure",
            "mode": mode
        }
        if iso is not None:
            cmd["iso"] = max(20.0, min(3200.0, float(iso)))
        if duration_seconds is not None:
            cmd["duration_seconds"] = max(0.0001, min(0.1, float(duration_seconds)))
        return self._send_command(cmd)

    def set_white_balance(self, mode: str = "continuous_auto", temperature_kelvin: float = 5500.0, tint: float = 0.0):
        cmd = {
            "type": "set_parameter",
            "parameter": "white_balance",
            "mode": mode,
            "temperature_kelvin": max(2000.0, min(10000.0, float(temperature_kelvin))),
            "tint": max(-150.0, min(150.0, float(tint)))
        }
        return self._send_command(cmd)

    def set_lens(self, lens: str):
        cmd = {
            "type": "set_parameter",
            "parameter": "lens",
            "lens": lens
        }
        return self._send_command(cmd)

    def set_torch(self, level: float):
        cmd = {
            "type": "set_parameter",
            "parameter": "torch",
            "level": max(0.0, min(1.0, float(level)))
        }
        return self._send_command(cmd)

    def set_zoom(self, factor: float):
        cmd = {
            "type": "set_parameter",
            "parameter": "zoom",
            "factor": max(1.0, min(10.0, float(factor)))
        }
        return self._send_command(cmd)
