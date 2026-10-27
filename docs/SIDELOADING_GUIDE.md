# Guía Paso a Paso: Instalación de OpticLink en tu iPhone (Sideloading sin Mac)

Esta guía te muestra exactamente cómo descargar el archivo `.ipa` compilado en la nube por GitHub Actions e instalarlo en tu iPhone en pocos minutos, sin necesidad de tener una computadora Mac.

---

## Paso 1: Subir el proyecto a GitHub y Descargar el .IPA

1. Crea un repositorio en tu cuenta de GitHub (puedes llamarlo `opticlink` o como prefieras).
2. Sube la carpeta del proyecto a tu repositorio:
   ```bash
   cd /home/pececito/.gemini/antigravity/scratch/opticlink
   git init
   git add .
   git commit -m "Initial release of OpticLink"
   git branch -M main
   git remote add origin https://github.com/TU_USUARIO/opticlink.git
   git push -u origin main
   ```
3. En tu repositorio de GitHub en el navegador:
   * Ve a la pestaña **Actions**.
   * Verás el flujo **"Build OpticLink iOS IPA"** ejecutándose en una máquina virtual macOS de Apple.
   * Al finalizar (tarda aproximadamente 2-3 minutos), haz clic en la ejecución y verás abajo el artefacto descargable: **`OpticLink-iOS-IPA`**.
   * Descárgalo y descomprime el archivo `.zip`: dentro tendrás tu archivo **`OpticLink.ipa`**.

---

## Paso 2: Instalar el .IPA en el iPhone

Elige el método que te sea más cómodo:

### Método A: SideStore (El más autónomo - Se instala una sola vez y no vuelves a usar PC)

SideStore te permite instalar y renovar apps directamente desde el iPhone conectándose a un servidor local WireGuard.
1. Abre [sidestore.io](https://sidestore.io) y sigue las instrucciones para instalar SideStore en tu iPhone.
2. Abre Safari en tu iPhone, descarga tu archivo `OpticLink.ipa` desde tu GitHub o pásatelo por Google Drive / Telegram.
3. Abre la app **SideStore** en tu iPhone, ve a la pestaña **My Apps**, toca el botón **`+`** en la esquina superior y selecciona `OpticLink.ipa`.
4. ¡Listo! La app se instalará en tu pantalla de inicio como cualquier otra aplicación.

---

### Método B: Sideloadly (Rápido y guiado por cable USB)

1. Conecta tu iPhone a la laptop con su cable USB.
2. Abre **Sideloadly**.
3. Arrastra el archivo `OpticLink.ipa` a la ventana de Sideloadly.
4. Escribe tu Apple ID (es el correo con el que usas tu iPhone; solo se usa para solicitar a Apple el certificado gratuito de desarrollador).
5. Pulsa **Start**. En menos de 60 segundos la app estará en tu iPhone.

---

## Paso 3: Confiar en el Certificado en iOS (Solo la primera vez)

Por seguridad de Apple, cuando instalas una app propia por primera vez, iOS te pedirá confirmar que confías en tu propio certificado de desarrollador:
1. En tu iPhone, ve a **Ajustes > General > Administración de dispositivos y VPN**.
2. En la sección *App de desarrollador*, toca sobre tu correo de Apple ID.
3. Pulsa en **"Confiar en [Tu Correo]"** y confirma.
4. Si tienes iOS 16 o superior, asegúrate de tener activado el *Modo de desarrollador* en **Ajustes > Privacidad y seguridad > Modo de desarrollador** (te pedirá reiniciar el iPhone una vez).

---

## Paso 4: ¡A transmitir!

1. Abre **OpticLink** en tu iPhone. Verás tu IP local en pantalla (ejemplo: `192.168.1.100`).
2. En tu laptop (Bazzite), abre el panel de control:
   ```bash
   cd /home/pececito/.gemini/antigravity/scratch/opticlink/linux
   python3 app.py
   ```
3. Ingresa la IP que muestra el iPhone (o usa el cable USB) y presiona **Conectar Cámara**.
4. ¡Abre Zoom, Meet, Discord o la app Cámara en tu laptop! Verás la señal de tu iPhone con todos los controles milimétricos respondiendo en tiempo real.
