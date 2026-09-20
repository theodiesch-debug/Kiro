#!/usr/bin/env bash

set -e

FILE="src/agent.py"
BACKUP="src/agent.py.backup"

echo "========================================"
echo "   Entferne ai-coustics aus Kiro"
echo "========================================"

if [ ! -f "$FILE" ]; then
    echo "✗ $FILE wurde nicht gefunden"
    exit 1
fi

echo
echo "[1/4] Backup erstellen..."

cp "$FILE" "$BACKUP"

echo "✓ Backup: $BACKUP"

echo
echo "[2/4] ai-coustics Import entfernen..."

python3 <<'PY'
from pathlib import Path

file = Path("src/agent.py")
text = file.read_text()

lines = text.splitlines()

new_lines = []

for line in lines:
    stripped = line.strip()

    # Import entfernen
    if "from livekit.plugins import ai_coustics" in line:
        print(f"ENTFERNT: {line}")
        continue

    if "import ai_coustics" in line:
        print(f"ENTFERNT: {line}")
        continue

    new_lines.append(line)

file.write_text("\n".join(new_lines) + "\n")
PY

echo "✓ Import entfernt"

echo
echo "[3/4] Prüfe verbleibende ai-coustics Stellen..."

if grep -n "ai_coustics" "$FILE"; then
    echo
    echo "⚠ Es gibt noch ai_coustics-Verwendungen."
    echo
    echo "Diese müssen ebenfalls entfernt werden."
    echo
    echo "Die Datei wurde NICHT weiter verändert."
    exit 1
else
    echo "✓ Keine ai_coustics-Verwendungen mehr gefunden"
fi

echo
echo "[4/4] Python-Syntax prüfen..."

if python3 -m py_compile "$FILE"; then
    echo "✓ Python-Syntax ist OK"
else
    echo
    echo "✗ Syntaxfehler!"
    echo "Backup wiederherstellen..."

    cp "$BACKUP" "$FILE"

    echo "✓ Original wiederhergestellt"
    exit 1
fi

echo
echo "========================================"
echo "✓ Fertig"
echo "========================================"

echo
echo "Backup:"
echo "  $BACKUP"

echo
echo "Starte jetzt mit:"
echo
echo "  ./start_kiro.sh"
echo
