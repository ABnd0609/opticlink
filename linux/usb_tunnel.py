import socket
import struct
import plistlib
import threading
from typing import Optional, Tuple, Dict, Any

USBMUXD_SOCKET_PATH = "/var/run/usbmuxd"

class USBTunnel:
    """
    Módulo para comunicación directa por cable USB con dispositivos iOS
    a través del daemon del sistema usbmuxd sin requerir binarios externos.
    """
    def __init__(self):
        self.device_id: Optional[int] = None
        self.udid: Optional[str] = None
        self._connected = False

    def find_connected_device(self) -> Optional[Tuple[int, str]]:
        """
        Consulta a usbmuxd si hay un iPhone/iPad conectado por cable USB.
        Retorna (device_id, udid) si se encuentra uno.
        """
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(2.0)
            s.connect(USBMUXD_SOCKET_PATH)
            
            # Mensaje Listen para enumerar dispositivos conectados
            req = {
                "MessageType": "Listen",
                "ClientVersionString": "OpticLink-Linux-1.0",
                "ProgName": "OpticLink"
            }
            self._send_plist(s, req)
            
            # Recibir respuesta de Attach
            resp = self._recv_plist(s)
            s.close()
            
            if resp and resp.get("MessageType") == "Attached":
                dev_props = resp.get("Properties", {})
                self.device_id = dev_props.get("DeviceID")
                self.udid = dev_props.get("SerialNumber")
                return (self.device_id, self.udid)
        except Exception:
            pass
        return None

    def connect_device_port(self, device_id: int, target_port: int) -> Optional[socket.socket]:
        """
        Establece un túnel bidireccional TCP con un puerto interno del iPhone por USB.
        target_port: ej. 8554 (video) u 8555 (control).
        """
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(USBMUXD_SOCKET_PATH)
            
            # El puerto debe estar en network byte order (big-endian)
            port_network_order = socket.htons(target_port)
            
            req = {
                "MessageType": "Connect",
                "ClientVersionString": "OpticLink-Linux-1.0",
                "ProgName": "OpticLink",
                "DeviceID": device_id,
                "PortNumber": port_network_order
            }
            self._send_plist(s, req)
            
            resp = self._recv_plist(s)
            if resp and resp.get("Number") == 0: # 0 significa éxito en usbmuxd
                return s
            else:
                s.close()
        except Exception as e:
            print(f"OpticLink USB: Error en túnel USB al puerto {target_port}: {e}")
        return None

    def _send_plist(self, sock: socket.socket, payload: Dict[str, Any]):
        data = plistlib.dumps(payload, fmt=plistlib.FMT_XML)
        length = 16 + len(data)
        # Header usbmuxd: length (4 bytes), version (4 bytes), request (4 bytes), tag (4 bytes)
        header = struct.pack("<IIII", length, 1, 8, 1)
        sock.sendall(header + data)

    def _recv_plist(self, sock: socket.socket) -> Optional[Dict[str, Any]]:
        raw_header = sock.recv(16)
        if len(raw_header) < 16:
            return None
        length, version, resp_type, tag = struct.unpack("<IIII", raw_header)
        payload_len = length - 16
        payload = b""
        while len(payload) < payload_len:
            chunk = sock.recv(min(4096, payload_len - len(payload)))
            if not chunk:
                break
            payload += chunk
        return plistlib.loads(payload)
