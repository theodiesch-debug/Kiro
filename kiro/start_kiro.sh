#!/usr/bin/env bash

set -e

echo "======================================"
echo "       KIRO / LIVEKIT START"
echo "======================================"

cd "$(dirname "$0")"

echo
echo "Projekt:"
pwd

echo
echo "LiveKit Agents Version:"
uv run python -c "import importlib.metadata; print(importlib.metadata.version('livekit-agents'))"

echo
echo "Teste LiveKit Import..."

if uv run python -c "import livekit.agents; print('IMPORT OK')"; then
    echo "✓ LiveKit Agents kann geladen werden"
else
    echo "✗ LiveKit Agents konnte nicht geladen werden"
    exit 1
fi

echo
echo "======================================"
echo "Starte Kiro..."
echo "======================================"
echo

exec uv run python src/agent.py dev
