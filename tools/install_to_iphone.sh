#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALTSERVER="$DIR/AltServer"
export ALTSERVER_ANISETTE_SERVER="http://127.0.0.1:6969"

echo "=========================================================="
echo "   OpticLink: Instalador Nativo de IPA en iOS para Linux"
echo "=========================================================="

# 1. Verificar si hay un iPhone conectado por USB
echo "[1/4] Detectando iPhone conectado por cable USB..."
UDID=$(ideviceinfo -k UniqueDeviceID 2>/dev/null || true)

if [ -z "$UDID" ]; then
    echo "❌ Error: No se detectó ningún iPhone por USB."
    echo "Asegúrate de:"
    echo " 1. Conectar tu iPhone por cable a la laptop."
    echo " 2. Desbloquear la pantalla."
    echo " 3. Tocar 'Confiar en esta computadora' si aparece el aviso."
    exit 1
fi

echo "✅ iPhone detectado con éxito (UDID: $UDID)"

# 2. Localizar el archivo OpticLink.ipa
IPA_PATH=""
if [ -f "$1" ]; then
    IPA_PATH="$1"
elif [ -f "$DIR/../OpticLink.ipa" ]; then
    IPA_PATH="$DIR/../OpticLink.ipa"
elif [ -f "$HOME/Downloads/OpticLink.ipa" ] || [ -f "$HOME/Descargas/OpticLink.ipa" ]; then
    IPA_PATH=$(ls -t "$HOME"/Descargas/OpticLink.ipa "$HOME"/Downloads/OpticLink.ipa 2>/dev/null | head -n 1)
fi

if [ -z "$IPA_PATH" ] || [ ! -f "$IPA_PATH" ]; then
    echo "⚠️ Por favor ingresa la ruta del archivo OpticLink.ipa descargado:"
    read -r IPA_PATH
fi

echo "[2/4] Archivo instalable seleccionado: $IPA_PATH"

# 3. Solicitar credenciales de Apple ID para la firma gratuita
echo ""
echo "[3/4] Autenticación para firma de desarrollo gratuita de Apple:"
read -p "Ingresa tu Apple ID (ej. tu_correo@icloud.com): " APPLE_ID
read -s -p "Ingresa tu contraseña de Apple ID (o App-Specific Password): " APPLE_PASS
echo ""

# 4. Instalar en el iPhone
echo ""
echo "[4/4] Firmando e instalando OpticLink en tu iPhone..."
if "$ALTSERVER" -u "$UDID" -a "$APPLE_ID" -p "$APPLE_PASS" "$IPA_PATH"; then
    echo ""
    echo "🎉 ¡LISTO! La app OpticLink ya está instalada en tu iPhone."
    echo "En tu iPhone, ve a Ajustes > General > Administración de dispositivos y pulsa 'Confiar'."
else
    echo ""
    echo "❌ Ocurrió un error al firmar o instalar la app en el iPhone."
    exit 1
fi
