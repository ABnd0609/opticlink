#!/usr/bin/env python3
import sys
import os
import time
import socket
import threading
import json

# Agregar ruta de módulos de linux
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "linux")))

from camera_controller import CameraController
from video_receiver import VideoReceiver

def run_tests():
    print("=" * 60)
    print("   OpticLink Suite de Pruebas de Integración y V4L2")
    print("=" * 60)
    
    passed = 0
    total = 0

    # Test 1: Verificar existencia del dispositivo /dev/video0
    total += 1
    print("\n[Test 1] Verificando dispositivo de cámara virtual /dev/video0...")
    if os.path.exists("/dev/video0"):
        print(" -> PASÓ: /dev/video0 detectado en el kernel.")
        passed += 1
    else:
        print(" -> FALLÓ: /dev/video0 no existe.")

    # Test 2: Validación de pipeline GStreamer hacia /dev/video0
    total += 1
    print("\n[Test 2] Probando inyección de fotogramas YUY2 con GStreamer...")
    receiver = VideoReceiver(device="/dev/video0")
    ok = receiver.start_test_pattern()
    if ok and receiver.is_running:
        time.sleep(1.5)
        receiver.stop()
        print(" -> PASÓ: GStreamer escribió con éxito en /dev/video0 y se detuvo limpiamente.")
        passed += 1
    else:
        print(" -> FALLÓ: No se pudo arrancar el pipeline de GStreamer.")

    # Test 3: Comunicación RPC y serialización JSON de comandos
    total += 1
    print("\n[Test 3] Probando servidor mock y cliente RPC de control de cámara...")
    received_commands = []
    server_running = True

    def mock_server():
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("127.0.0.1", 18555))
        srv.listen(1)
        srv.settimeout(3.0)
        try:
            conn, _ = srv.accept()
            f = conn.makefile("r")
            while server_running:
                line = f.readline()
                if not line:
                    break
                received_commands.append(json.loads(line))
            conn.close()
        except socket.timeout:
            pass
        finally:
            srv.close()

    t = threading.Thread(target=mock_server, daemon=True)
    t.start()
    time.sleep(0.2)

    controller = CameraController(host="127.0.0.1", port=18555)
    connected = controller.connect()
    
    if connected:
        controller.set_focus("manual", 0.75)
        controller.set_exposure("manual", iso=400, duration_seconds=0.0166)
        controller.set_white_balance("manual", temperature_kelvin=6000)
        controller.set_lens("ultra_wide")
        controller.set_torch(0.5)
        controller.set_zoom(2.0)
        time.sleep(0.3)
        controller.disconnect()
        server_running = False

        if len(received_commands) == 6:
            print(f" -> PASÓ: Los 6 comandos RPC fueron recibidos y validados correctamente.")
            passed += 1
        else:
            print(f" -> FALLÓ: Se esperaban 6 comandos, se recibieron {len(received_commands)}.")
    else:
        print(" -> FALLÓ: No se pudo conectar al socket mock RPC.")

    print("\n" + "=" * 60)
    print(f" Resultado Final: {passed}/{total} pruebas superadas.")
    print("=" * 60)
    return 0 if passed == total else 1

if __name__ == "__main__":
    sys.exit(run_tests())
