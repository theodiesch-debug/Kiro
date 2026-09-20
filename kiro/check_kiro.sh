#!/usr/bin/env bash
# check_kiro.sh — Diagnose + Auto-Fix für das Kiro LiveKit-Agent-Projekt
#
# Verwendung:
#   1. Diese Datei in den kiro/-Ordner legen (dort wo src/agent.py liegt)
#   2. chmod +x check_kiro.sh
#   3. ./check_kiro.sh
#
# Das Skript prüft Umgebung, Abhängigkeiten und startet den Agent testweise,
# um den echten Absturzgrund sichtbar zu machen. Wo möglich, behebt es
# Probleme automatisch (fehlende .env.local, fehlende Dependencies).

set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0

ok()   { echo -e "  ${GREEN}✔${NC} $1"; PASS=$((PASS+1)); }
bad()  { echo -e "  ${RED}✘${NC} $1"; FAIL=$((FAIL+1)); }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fixhint() { echo -e "    ${YELLOW}→ Fix:${NC} $1"; }
section() { echo -e "\n${BLUE}== $1 ==${NC}"; }

cd "$(dirname "$0")" || { echo "Konnte nicht ins Skript-Verzeichnis wechseln."; exit 1; }

section "1. Projektstruktur"
if [ -f "src/agent.py" ]; then
    ok "src/agent.py gefunden — richtiges Verzeichnis"
else
    bad "src/agent.py NICHT gefunden — liegt dieses Skript im kiro-Ordner?"
    echo "Abbruch, da alle weiteren Checks davon abhängen."
    exit 1
fi

section "2. Benötigte Programme"
if command -v lk >/dev/null 2>&1; then
    ok "lk (LiveKit CLI) installiert — $(lk --version 2>/dev/null | head -n1)"
else
    bad "lk (LiveKit CLI) nicht gefunden"
    fixhint "curl -sSL https://get.livekit.io/cli | bash"
fi

if command -v uv >/dev/null 2>&1; then
    ok "uv installiert — $(uv --version 2>/dev/null)"
else
    bad "uv nicht gefunden — ohne uv kann der Rest nicht laufen"
    fixhint "curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
fi

section "3. .env.local"
if [ -f ".env.local" ]; then
    ok ".env.local vorhanden"
else
    warn ".env.local fehlt — versuche automatische Erzeugung"
    if command -v lk >/dev/null 2>&1; then
        if lk app env -w -d .env.local >/tmp/kiro_env.log 2>&1; then
            ok ".env.local automatisch aus dem LiveKit-Cloud-Projekt erzeugt"
        else
            bad "Automatische Erzeugung fehlgeschlagen (siehe /tmp/kiro_env.log)"
            fixhint "lk cloud auth erneut ausführen, dann lk app env -w -d .env.local"
        fi
    else
        bad "Kann .env.local nicht automatisch erzeugen (lk fehlt)"
    fi
fi

if [ -f ".env.local" ]; then
    for var in LIVEKIT_URL LIVEKIT_API_KEY LIVEKIT_API_SECRET; do
        val=$(grep -E "^${var}=" .env.local 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '"'"'"' \r')
        if [ -z "$val" ]; then
            bad "$var fehlt oder ist leer"
            fixhint "In .env.local eintragen, z.B. per: lk app env -w -d .env.local"
        else
            ok "$var gesetzt"
            if [ "$var" = "LIVEKIT_URL" ] && [[ "$val" != wss://* ]]; then
                warn "LIVEKIT_URL beginnt nicht mit wss:// — Wert: $val"
            fi
        fi
    done
fi

section "4. Python-Abhängigkeiten"
echo "  Führe 'uv sync' aus ..."
if uv sync >/tmp/kiro_uv_sync.log 2>&1; then
    ok "uv sync erfolgreich"
else
    bad "uv sync fehlgeschlagen"
    echo "  ---- Ausschnitt aus /tmp/kiro_uv_sync.log ----"
    tail -n 20 /tmp/kiro_uv_sync.log | sed 's/^/    /'
    echo "  -----------------------------------------------"
fi

PYV=$(uv run python --version 2>&1)
echo "  Python-Version: $PYV"

for mod in livekit.agents livekit.plugins.ai_coustics dotenv; do
    if uv run python -c "import ${mod}" >/dev/null 2>&1; then
        ok "Modul '$mod' importierbar"
    else
        bad "Modul '$mod' NICHT importierbar"
        fixhint "uv sync erneut ausführen, oder uv add <fehlendes-paket>"
    fi
done

section "5. Lokale Modell-Dateien (falls benötigt)"
if grep -qE "silero|MultilingualModel|turn_detector\.(model|EOU)" src/agent.py 2>/dev/null; then
    echo "  Lokale VAD/Turn-Detector-Modelle im Code erkannt, lade Modell-Dateien ..."
    if uv run python src/agent.py download-files >/tmp/kiro_download.log 2>&1; then
        ok "Modell-Dateien geladen"
    else
        bad "Download der Modell-Dateien fehlgeschlagen (siehe /tmp/kiro_download.log)"
    fi
else
    ok "Keine lokalen Modell-Dateien nötig (Cloud-Inference wird genutzt)"
fi

section "6. Testlauf des Agents (15 Sekunden)"
echo "  Starte: uv run python src/agent.py dev"
timeout 15 uv run python src/agent.py dev > /tmp/kiro_dev.log 2>&1
EXIT_CODE=$?

if [ $EXIT_CODE -eq 124 ]; then
    ok "Agent lief die vollen 15 Sekunden ohne Absturz — sieht gut aus"
    echo "  (Für den echten Betrieb: uv run python src/agent.py dev bzw. lk agent dev, ohne timeout)"
else
    bad "Agent ist vorzeitig beendet worden (Exit-Code $EXIT_CODE)"
    echo "  ---- Log-Ausschnitt (/tmp/kiro_dev.log) ----"
    tail -n 40 /tmp/kiro_dev.log | sed 's/^/    /'
    echo "  ----------------------------------------------"

    echo ""
    echo "  Bekannte Fehlermuster:"
    FOUND_PATTERN=0
    if grep -qi "ModuleNotFoundError\|ImportError" /tmp/kiro_dev.log; then
        bad "Fehlendes Python-Modul"
        fixhint "uv sync erneut ausführen; falls ein einzelnes Paket fehlt: uv add <paketname>"
        FOUND_PATTERN=1
    fi
    if grep -qi "invalid api key\|401\|unauthorized\|permission denied" /tmp/kiro_dev.log; then
        bad "Ungültiger oder fehlender API-Key"
        fixhint "LIVEKIT_API_KEY / LIVEKIT_API_SECRET in .env.local prüfen, ggf. lk app env -w -d .env.local neu ausführen"
        FOUND_PATTERN=1
    fi
    if grep -qi "connection refused\|getaddrinfo\|name resolution\|timed out" /tmp/kiro_dev.log; then
        bad "Netzwerk-/Verbindungsproblem"
        fixhint "Internetverbindung prüfen und LIVEKIT_URL in .env.local kontrollieren"
        FOUND_PATTERN=1
    fi
    if grep -qi "no such file or directory" /tmp/kiro_dev.log; then
        bad "Datei nicht gefunden (evtl. fehlende Modell-Dateien oder falscher Pfad)"
        fixhint "uv run python src/agent.py download-files ausführen"
        FOUND_PATTERN=1
    fi
    if grep -qi "port.*already in use\|address already in use" /tmp/kiro_dev.log; then
        bad "Port bereits belegt (läuft evtl. schon ein alter Agent-Prozess?)"
        fixhint "pkill -f 'src/agent.py' und erneut versuchen"
        FOUND_PATTERN=1
    fi
    if [ $FOUND_PATTERN -eq 0 ]; then
        warn "Kein bekanntes Fehlermuster erkannt — bitte den Log-Ausschnitt oben genau lesen"
    fi
fi

section "Zusammenfassung"
echo -e "  ${GREEN}Bestanden: $PASS${NC}   ${RED}Fehlgeschlagen: $FAIL${NC}"
echo "  Vollständige Logs liegen in /tmp/kiro_*.log"