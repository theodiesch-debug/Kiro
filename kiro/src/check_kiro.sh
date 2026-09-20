#!/usr/bin/env bash
# check_avx.sh — Findet heraus, ob die CPU AVX/AVX2 unterstützt und
# welches Python-Modul den SIGILL-Crash (Exit-Code 132) verursacht.
#
# Verwendung: im kiro-Ordner ausführen (dort wo .venv/pyproject.toml liegt)
#   chmod +x check_avx.sh
#   ./check_avx.sh

set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}== CPU-Features ==${NC}"
MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')
echo "  CPU: $MODEL"

FLAGS=$(grep -m1 flags /proc/cpuinfo)
for feat in sse4_2 avx avx2 avx512f; do
    if echo "$FLAGS" | grep -qw "$feat"; then
        echo -e "  ${GREEN}✔${NC} $feat unterstützt"
    else
        echo -e "  ${RED}✘${NC} $feat NICHT unterstützt"
    fi
done

echo -e "\n${BLUE}== Modul-Bisektion (findet das crashende Paket) ==${NC}"
echo "  Teste jedes Modul einzeln mit 'uv run python -c \"import X\"' ..."
echo ""

# Reihenfolge: von low-level (wahrscheinlichste Ursache) zu high-level
MODULES=(
    "numpy"
    "onnxruntime"
    "av"
    "grpc"
    "livekit"
    "livekit.rtc"
    "livekit.agents"
    "livekit.plugins.silero"
    "livekit.plugins.ai_coustics"
    "livekit.inference"
)

CULPRITS=()

for mod in "${MODULES[@]}"; do
    # Timeout schützt davor, dass ein Hänger das Skript blockiert
    timeout 10 uv run python -c "import ${mod}" >/tmp/avx_test_${mod//./_}.log 2>&1
    code=$?
    if [ $code -eq 0 ]; then
        echo -e "  ${GREEN}✔${NC} $mod  (ok)"
    elif [ $code -eq 132 ]; then
        echo -e "  ${RED}✘${NC} $mod  (SIGILL — CRASH, Illegal Instruction)"
        CULPRITS+=("$mod")
    elif [ $code -eq 1 ]; then
        # Meist ModuleNotFoundError, falls das Paket direkt nicht existiert
        reason=$(tail -n 1 /tmp/avx_test_${mod//./_}.log)
        echo -e "  ${YELLOW}⚠${NC} $mod  (nicht importierbar, aber kein SIGILL: $reason)"
    else
        echo -e "  ${YELLOW}⚠${NC} $mod  (Exit-Code $code, ungewöhnlich)"
    fi
done

echo -e "\n${BLUE}== Ergebnis ==${NC}"
if [ ${#CULPRITS[@]} -eq 0 ]; then
    echo "  Kein einzelnes Modul isoliert einen SIGILL-Crash."
    echo "  Der Crash tritt evtl. erst bei Kombination/Laufzeit auf (z.B. beim tatsächlichen VAD-Aufruf)."
else
    echo -e "  ${RED}Crash verursacht durch:${NC} ${CULPRITS[*]}"
    echo "  Logs dazu: /tmp/avx_test_<modulname>.log"
fi