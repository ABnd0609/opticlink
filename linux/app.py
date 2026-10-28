#!/usr/bin/env python3
import sys
import subprocess
import threading
import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("GLib", "2.0")
from gi.repository import Gtk, Adw, GLib, Gio

from camera_controller import CameraController
from video_receiver import VideoReceiver
from usb_tunnel import USBTunnel

class OpticLinkWindow(Adw.ApplicationWindow):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.set_default_size(720, 850)
        self.set_title("OpticLink Pro - Cámara iOS")

        self.controller = CameraController(on_state_change=self._on_controller_state)
        self.receiver = VideoReceiver(device="/dev/video0", on_status_change=self._on_receiver_status)
        self.usb_tunnel = USBTunnel()

        self.set_icon_name("opticlink")
        self._is_connecting = False
        self._build_ui()

    def _build_ui(self):
        # Layout principal
        toolbar_view = Adw.ToolbarView()
        self.set_content(toolbar_view)

        # Header Bar de GNOME / Adwaita
        header = Adw.HeaderBar()
        self.status_badge = Gtk.Label(label="Desconectado")
        self.status_badge.add_css_class("dim-label")
        header.set_title_widget(self.status_badge)
        toolbar_view.add_top_bar(header)

        # Contenedor con scroll
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_vexpand(True)
        toolbar_view.set_content(scrolled)

        clamp = Adw.Clamp()
        clamp.set_maximum_size(680)
        clamp.set_margin_top(16)
        clamp.set_margin_bottom(24)
        clamp.set_margin_start(16)
        clamp.set_margin_end(16)
        scrolled.set_child(clamp)

        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=20)
        clamp.set_child(main_box)

        # --- SECCIÓN 1: Conexión ---
        conn_group = Adw.PreferencesGroup(title="Conexión con el iPhone", description="Conecta por red local o cable USB")
        main_box.append(conn_group)

        # Fila IP del iPhone
        self.ip_row = Adw.EntryRow(title="Dirección IP del iPhone")
        self.ip_row.set_text("192.168.1.100")
        conn_group.add(self.ip_row)

        # Fila Dispositivo V4L2
        self.v4l2_row = Adw.EntryRow(title="Dispositivo de Cámara Virtual")
        self.v4l2_row.set_text("/dev/video0")
        conn_group.add(self.v4l2_row)

        # Fila de acciones de conexión
        conn_actions_row = Adw.ActionRow(title="Estado de Streaming")
        self.btn_connect = Gtk.Button(label="Conectar Cámara")
        self.btn_connect.add_css_class("suggested-action")
        self.btn_connect.connect("clicked", self._on_connect_clicked)

        self.btn_test = Gtk.Button(label="Probar Cámara Virtual")
        self.btn_test.connect("clicked", self._on_test_clicked)

        self.btn_open_cam = Gtk.Button(label="Ver Cámara en Pantalla")
        self.btn_open_cam.connect("clicked", lambda _: subprocess.Popen(["snapshot"]))

        box_btns = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        box_btns.append(self.btn_open_cam)
        box_btns.append(self.btn_test)
        box_btns.append(self.btn_connect)
        conn_actions_row.add_suffix(box_btns)
        conn_group.add(conn_actions_row)

        info_row = Adw.ActionRow(title="Dispositivo en Aplicaciones", subtitle="En Zoom, Meet, Teams o navegadores aparece como 'OBS Virtual Camera'")
        conn_group.add(info_row)

        # --- SECCIÓN 2: Lentes y Zoom ---
        lens_group = Adw.PreferencesGroup(title="Óptica y Selección de Cámara", description="Cambia entre los sensores reales del iPhone")
        main_box.append(lens_group)

        lens_row = Adw.ActionRow(title="Lente Activo")
        lens_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        
        for name, key in [("0.5x Ultra", "ultra_wide"), ("1x Gran Angular", "wide"), ("3x Tele", "telephoto"), ("Frontal", "front")]:
            btn = Gtk.Button(label=name)
            btn.connect("clicked", lambda b, k=key: self.controller.set_lens(k))
            lens_box.append(btn)
        lens_row.add_suffix(lens_box)
        lens_group.add(lens_row)

        # Zoom digital
        zoom_row = Adw.ActionRow(title="Zoom Digital")
        self.zoom_scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 1.0, 5.0, 0.1)
        self.zoom_scale.set_value(1.0)
        self.zoom_scale.set_size_request(200, -1)
        self.zoom_scale.connect("value-changed", lambda s: self.controller.set_zoom(s.get_value()))
        zoom_row.add_suffix(self.zoom_scale)
        lens_group.add(zoom_row)

        # Linterna / Luz de relleno
        torch_row = Adw.ActionRow(title="Luz de Relleno (Linterna)")
        self.torch_switch = Gtk.Switch()
        self.torch_switch.connect("state-set", lambda sw, st: (self.controller.set_torch(1.0 if st else 0.0), False)[1])
        torch_row.add_suffix(self.torch_switch)
        lens_group.add(torch_row)

        # --- SECCIÓN 3: Enfoque ---
        focus_group = Adw.PreferencesGroup(title="Enfoque", description="Ajuste fino de distancia focal")
        main_box.append(focus_group)

        focus_mode_row = Adw.ActionRow(title="Modo de Enfoque")
        self.focus_auto_switch = Gtk.Switch(active=True)
        self.focus_auto_switch.connect("state-set", self._on_focus_mode_changed)
        focus_mode_row.set_subtitle("Automático continuo activado")
        focus_mode_row.add_suffix(self.focus_auto_switch)
        self.focus_mode_row = focus_mode_row
        focus_group.add(focus_mode_row)

        focus_slider_row = Adw.ActionRow(title="Posición de Enfoque (Manual)")
        self.focus_scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0.0, 1.0, 0.01)
        self.focus_scale.set_value(0.5)
        self.focus_scale.set_size_request(220, -1)
        self.focus_scale.set_sensitive(False)
        self.focus_scale.connect("value-changed", lambda s: self.controller.set_focus("manual", s.get_value()))
        focus_slider_row.add_suffix(self.focus_scale)
        focus_group.add(focus_slider_row)

        # --- SECCIÓN 4: Exposición e ISO ---
        exp_group = Adw.PreferencesGroup(title="Exposición e ISO", description="Evita que la imagen se queme o esté oscura")
        main_box.append(exp_group)

        exp_mode_row = Adw.ActionRow(title="Modo de Exposición")
        self.exp_auto_switch = Gtk.Switch(active=True)
        self.exp_auto_switch.connect("state-set", self._on_exp_mode_changed)
        exp_mode_row.set_subtitle("Autoexposición continua activada")
        exp_mode_row.add_suffix(self.exp_auto_switch)
        self.exp_mode_row = exp_mode_row
        exp_group.add(exp_mode_row)

        iso_row = Adw.ActionRow(title="Sensibilidad ISO")
        self.iso_scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 50, 1600, 25)
        self.iso_scale.set_value(200)
        self.iso_scale.set_size_request(220, -1)
        self.iso_scale.set_sensitive(False)
        self.iso_scale.connect("value-changed", self._on_manual_exp_changed)
        iso_row.add_suffix(self.iso_scale)
        exp_group.add(iso_row)

        shutter_row = Adw.ActionRow(title="Velocidad de Obturación")
        self.shutter_scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 30, 1000, 10)
        self.shutter_scale.set_value(60)
        self.shutter_scale.set_size_request(220, -1)
        self.shutter_scale.set_sensitive(False)
        self.shutter_scale.connect("value-changed", self._on_manual_exp_changed)
        shutter_row.add_suffix(self.shutter_scale)
        exp_group.add(shutter_row)

        # --- SECCIÓN 5: Balance de Blancos ---
        wb_group = Adw.PreferencesGroup(title="Temperatura de Color", description="Ajuste de tonos cálidos y fríos en Kelvin")
        main_box.append(wb_group)

        wb_row = Adw.ActionRow(title="Temperatura (Kelvin)")
        self.wb_scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 2500, 9000, 100)
        self.wb_scale.set_value(5500)
        self.wb_scale.set_size_request(220, -1)
        self.wb_scale.connect("value-changed", lambda s: self.controller.set_white_balance("manual", s.get_value()))
        wb_row.add_suffix(self.wb_scale)
        wb_group.add(wb_row)

    def _on_focus_mode_changed(self, switch, active):
        self.focus_scale.set_sensitive(not active)
        self.focus_mode_row.set_subtitle("Automático continuo activado" if active else "Control manual habilitado")
        if active:
            self.controller.set_focus("continuous_auto")
        else:
            self.controller.set_focus("manual", self.focus_scale.get_value())
        return False

    def _on_exp_mode_changed(self, switch, active):
        self.iso_scale.set_sensitive(not active)
        self.shutter_scale.set_sensitive(not active)
        self.exp_mode_row.set_subtitle("Autoexposición continua activada" if active else "Control manual habilitado")
        if active:
            self.controller.set_exposure("continuous_auto")
        else:
            self._on_manual_exp_changed()
        return False

    def _on_manual_exp_changed(self, *args):
        if not self.exp_auto_switch.get_active():
            iso = self.iso_scale.get_value()
            shutter_denom = self.shutter_scale.get_value()
            duration = 1.0 / max(1.0, shutter_denom)
            self.controller.set_exposure("manual", iso=iso, duration_seconds=duration)

    def _on_connect_clicked(self, btn):
        if self._is_connecting:
            return

        ip = self.ip_row.get_text().strip()
        v4l2_dev = self.v4l2_row.get_text().strip()
        self.receiver.device = v4l2_dev

        if not self.controller.is_connected:
            self._is_connecting = True
            btn.set_label("Conectando...")
            btn.set_sensitive(False)
            
            # Ejecutar intento de conexión en hilo secundario para NO congelar la interfaz GTK (Blindaje Hallazgo 1)
            threading.Thread(target=self._async_connect_worker, args=(ip,), daemon=True).start()
        else:
            self.controller.disconnect()
            self.receiver.stop()
            self._update_button_disconnected()

    def _async_connect_worker(self, ip: str):
        ok = self.controller.connect(host=ip, port=8555)
        if ok:
            self.receiver.start_network_stream(host=ip, port=8554)
            self.controller.start_watchdog()
            GLib.idle_add(self._update_button_connected)
        else:
            GLib.idle_add(self._update_button_disconnected)

    def _update_button_connected(self):
        self._is_connecting = False
        self.btn_connect.set_label("Desconectar")
        self.btn_connect.remove_css_class("suggested-action")
        self.btn_connect.add_css_class("destructive-action")
        self.btn_connect.set_sensitive(True)

    def _update_button_disconnected(self):
        self._is_connecting = False
        self.btn_connect.set_label("Conectar Cámara")
        self.btn_connect.remove_css_class("destructive-action")
        self.btn_connect.add_css_class("suggested-action")
        self.btn_connect.set_sensitive(True)

    def _on_test_clicked(self, btn):
        if not self.receiver.is_running:
            self.receiver.device = self.v4l2_row.get_text().strip()
            ok = self.receiver.start_test_pattern()
            if ok:
                btn.set_label("Detener Prueba")
        else:
            self.receiver.stop()
            btn.set_label("Probar Cámara Virtual")

    def _on_controller_state(self, connected: bool, message: str):
        GLib.idle_add(self._update_status_ui, connected, message)

    def _on_receiver_status(self, message: str):
        GLib.idle_add(self.status_badge.set_text, message)

    def _update_status_ui(self, connected: bool, message: str):
        self.status_badge.set_text(message)
        if connected:
            self.status_badge.remove_css_class("dim-label")
            self.status_badge.add_css_class("accent")
        else:
            self.status_badge.remove_css_class("accent")
            self.status_badge.add_css_class("dim-label")

class OpticLinkApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id="com.opticlink.desktop", flags=Gio.ApplicationFlags.FLAGS_NONE)

    def do_activate(self):
        win = self.props.active_window
        if not win:
            win = OpticLinkWindow(application=self)
        win.present()

if __name__ == "__main__":
    app = OpticLinkApp()
    sys.exit(app.run(sys.argv))
