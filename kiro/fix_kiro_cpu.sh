#!/usr/bin/env bash

set -e

echo "========================================"
echo "   LiveKit CPU-Kompatibilitäts-Fix"
echo "========================================"

# Sicherstellen, dass wir im Projektordner sind
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo
echo "Projekt: $PROJECT_DIR"

# -------------------------------------------------
# 1. Backup
# -------------------------------------------------

echo
echo "[1/5] Backup erstellen..."

cp pyproject.toml pyproject.toml.backup

if [ -f uv.lock ]; then
    cp uv.lock uv.lock.backup
fi

echo "✓ Backup erstellt"

# -------------------------------------------------
# 2. LiveKit Agents auf 1.5.2 setzen
# -------------------------------------------------

echo
echo "[2/5] LiveKit Agents auf 1.5.2 setzen..."

uv add "livekit-agents==1.5.2"

echo "✓ livekit-agents 1.5.2 gesetzt"

# -------------------------------------------------
# 3. ai-coustics entfernen
# -------------------------------------------------

echo
echo "[3/5] ai-coustics entfernen..."

uv remove livekit-plugins-ai-coustics 2>/dev/null || true

echo "✓ ai-coustics aus den Dependencies entfernt"

# -------------------------------------------------
# 4. Dependencies neu installieren
# -------------------------------------------------

echo
echo "[4/5] Dependencies synchronisieren..."

uv sync

echo "✓ uv sync erfolgreich"

# -------------------------------------------------
# 5. CPU-Test
# -------------------------------------------------

echo
echo "[5/5] LiveKit Import testen..."

set +e

uv run python -c "import livekit.agents; print('LIVEKIT_IMPORT_OK')" \
    >/tmp/kiro_livekit_test.log 2>&1

CODE=$?

set -e

if [ "$CODE" -eq 0 ]; then
    echo
    echo "========================================"
    echo "✓ LIVEKIT IMPORT FUNKTIONIERT"
    echo "========================================"
    echo
    echo "Starte jetzt:"
    echo
    echo "    lk agent dev"
    echo
else

    echo
    echo "========================================"
    echo "✗ LIVEKIT IMPORT SCHLÄGT NOCH FEHL"
    echo "========================================"
    echo
    echo "Log:"
    cat /tmp/kiro_livekit_test.log
    echo

    if [ "$CODE" -eq 132 ]; then
        echo "Der Rechner stürzt weiterhin wegen SIGILL ab."
        echo "Dann reicht das Downgrade alleine leider nicht."
    fi

    exit "$CODE"
fi
