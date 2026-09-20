#!/usr/bin/env bash

set -e

FILE="src/agent.py"

echo "========================================"
echo "   Entferne LiveKit Noise Cancellation"
echo "========================================"

if [ ! -f "$FILE" ]; then
    echo "✗ $FILE nicht gefunden"
    exit 1
fi

echo
echo "[1/4] Backup erstellen..."

cp "$FILE" "${FILE}.before-noise-fix"

echo "✓ Backup erstellt"

echo
echo "[2/4] noise_cancellation Block entfernen..."

python3 <<'PY'
from pathlib import Path

path = Path("src/agent.py")
lines = path.read_text().splitlines()

result = []
removing = False
depth = 0
found = False

for line in lines:
    stripped = line.strip()

    if not removing and "noise_cancellation=ai_coustics.audio_enhancement(" in line:
        print("ENTFERNT:")
        print(line)
        removing = True
        found = True

        # Klammern in dieser Startzeile zählen
        depth = line.count("(") - line.count(")")
        continue

    if removing:
        print(line)

        depth += line.count("(") - line.count(")")

        if depth <= 0:
            removing = False

        continue

    result.append(line)

if not found:
    print("✗ Kein noise_cancellation Block gefunden")
    raise SystemExit(1)

path.write_text("\n".join(result) + "\n")

print("✓ noise_cancellation Block entfernt")
PY

echo
echo "[3/4] Suche nach ai_coustics..."

if grep -n "ai_coustics" "$FILE"; then
    echo
    echo "⚠ Es gibt noch ai_coustics-Verwendungen."
    echo
    echo "Bitte diese Ausgabe schicken."
    exit 1
else
    echo "✓ Keine ai_coustics-Verwendungen mehr"
fi

echo
echo "[4/4] Python-Syntax prüfen..."

if python3 -m py_compile "$FILE"; then
    echo "✓ Python-Syntax OK"
else
    echo "✗ Syntaxfehler!"
    echo
    echo "Backup wird wiederhergestellt..."

    cp "${FILE}.before-noise-fix" "$FILE"

    echo "✓ Backup wiederhergestellt"
    exit 1
fi

echo
echo "========================================"
echo "✓ Fertig"
echo "========================================"

echo
echo "Jetzt starten mit:"
echo
echo "    ./start_kiro.sh"
echo
