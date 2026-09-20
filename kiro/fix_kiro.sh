#!/usr/bin/env bash
set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✔${NC} $1"; }
bad()  { echo -e "  ${RED}✘${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
section() { echo -e "\n${BLUE}== $1 ==${NC}"; }

# ---------- Phase 0: Projekt automatisch finden, egal wo wir stehen ----------
section "0. Projektordner finden"
find_project_root() {
    if [ -f "src/agent.py" ]; then pwd; return 0; fi
    if [ -f "kiro/src/agent.py" ]; then (cd kiro && pwd); return 0; fi
    if [ -f "$HOME/Coding/projekte/Kiro/kiro/src/agent.py" ]; then
        echo "$HOME/Coding/projekte/Kiro/kiro"; return 0
    fi
    local found
    found=$(find "$HOME" -maxdepth 7 -type f -path "*/kiro/src/agent.py" 2>/dev/null | head -n1)
    if [ -n "$found" ]; then dirname "$(dirname "$found")"; return 0; fi
    return 1
}

PROJECT_ROOT=$(find_project_root) || { bad "Konnte src/agent.py nirgends finden. Bitte im kiro-Ordner ausführen."; exit 1; }
cd "$PROJECT_ROOT" || exit 1
ok "Projekt gefunden: $PROJECT_ROOT"

# ---------- Phase 1: Grundcheck ----------
section "1. Grundcheck"
command -v uv >/dev/null 2>&1 || { bad "uv fehlt. https://astral.sh/uv/install.sh"; exit 1; }
command -v lk >/dev/null 2>&1 || warn "lk (LiveKit CLI) nicht gefunden — Endstart läuft dann über uv statt lk"

if [ ! -f ".env.local" ] && command -v lk >/dev/null 2>&1; then
    lk app env -w -d .env.local >/tmp/kiro_env.log 2>&1 && ok ".env.local erzeugt" || bad ".env.local konnte nicht erzeugt werden"
else
    ok ".env.local vorhanden"
fi

echo "  uv sync ..."
uv sync >/tmp/kiro_uv_sync.log 2>&1 && ok "Dependencies installiert" || { bad "uv sync fehlgeschlagen, siehe /tmp/kiro_uv_sync.log"; exit 1; }

# ---------- Phase 2: CPU-kompatible BLAS-Variante suchen ----------
section "2. Suche CPU-kompatible Konfiguration (SIGILL-Fix)"
MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')
echo "  CPU: $MODEL"

NPY_FEATURES="AVX2 AVX512F AVX512_SKX AVX512_CLX AVX512_CNL AVX512_ICL FMA3 AVX F16C"

try_env() {
    local coretype="$1"
    OPENBLAS_CORETYPE="$coretype" NPY_DISABLE_CPU_FEATURES="$NPY_FEATURES" \
        timeout 10 uv run python -c "import livekit.agents; import livekit.plugins.ai_coustics" \
        > "/tmp/kiro_trial_${coretype}.log" 2>&1
    return $?
}

WORKING_CORETYPE=""
for ct in Westmere Nehalem Core2 Prescott Generic; do
    echo "  Teste OPENBLAS_CORETYPE=$ct ..."
    if try_env "$ct"; then
        ok "Erfolg mit OPENBLAS_CORETYPE=$ct"
        WORKING_CORETYPE="$ct"
        break
    else
        echo "    weiterhin Absturz"
    fi
done

if [ -z "$WORKING_CORETYPE" ]; then
    section "Kein automatischer Fix gefunden"
    bad "Keine der getesteten CPU-Varianten hat den Crash behoben."
    echo "  Ermittle die genaue Python-Absturzstelle als Nächstes ..."
    uv run python -X faulthandler -c "import livekit.agents" > /tmp/kiro_faulthandler_agents.log 2>&1
    uv run python -X faulthandler -c "import livekit.plugins.ai_coustics" > /tmp/kiro_faulthandler_aicoustics.log 2>&1
    echo ""
    echo "  ---- Stack bei 'import livekit.agents' ----"
    cat /tmp/kiro_faulthandler_agents.log
    echo "  ---- Stack bei 'import livekit.plugins.ai_coustics' ----"
    cat /tmp/kiro_faulthandler_aicoustics.log
    echo ""
    warn "Nichts wurde gelöscht — schick mir die beiden Stacks oben, dann grenzen wir den genauen Verursacher ein."
    exit 1
fi

# ---------- Phase 3: Persistenten Start-Wrapper schreiben ----------
section "3. Persistenten Fix als run_dev.sh speichern"
cat > run_dev.sh << WRAPEOF
#!/usr/bin/env bash
# Automatisch erzeugt von fix_kiro.sh — setzt die für diese CPU passende
# BLAS-Kernel-Variante, damit livekit.agents nicht mit SIGILL abstürzt.
export OPENBLAS_CORETYPE=$WORKING_CORETYPE
export NPY_DISABLE_CPU_FEATURES="$NPY_FEATURES"
cd "\$(dirname "\$0")"
if command -v lk >/dev/null 2>&1; then
    exec lk agent dev "\$@"
else
    exec uv run python src/agent.py dev "\$@"
fi
WRAPEOF
chmod +x run_dev.sh
ok "run_dev.sh geschrieben (dein zukünftiger Startbefehl: ./run_dev.sh)"

# ---------- Phase 4: Echten Testlauf mit dem Fix ----------
section "4. Echter Testlauf (20 Sekunden) mit dem Fix"
timeout 20 ./run_dev.sh > /tmp/kiro_final_test.log 2>&1
code=$?

if [ $code -ne 124 ] && [ $code -ne 0 ]; then
    bad "Import ist jetzt stabil, aber der volle Agent stürzt trotzdem ab (Exit $code)"
    echo "  ---- Log-Ausschnitt ----"
    tail -n 40 /tmp/kiro_final_test.log | sed 's/^/    /'
    warn "Logs bleiben liegen (/tmp/kiro_final_test.log), run_dev.sh bleibt bestehen. Schick mir den Ausschnitt."
    exit 1
fi

ok "Agent läuft stabil mit OPENBLAS_CORETYPE=$WORKING_CORETYPE"

# ---------- Phase 5: Aufräumen (nur bei Erfolg) ----------
section "5. Aufräumen"
rm -f check_kiro.sh check_avx.sh
rm -f /tmp/kiro_*.log /tmp/avx_test_*.log /tmp/kiro_trial_*.log
ok "Alle Test-/Debug-Dateien gelöscht"
echo "  (run_dev.sh bleibt — das ist ab jetzt dein Startbefehl, kein Testfile)"

# ---------- Phase 6: Im Browser öffnen und starten ----------
section "6. Start"
CONSOLE_URL="https://cloud.livekit.io/projects/p_/agents/console/?autoStart=true&agentName=kiro"
echo "  Konsole: $CONSOLE_URL"
( command -v xdg-open >/dev/null 2>&1 && xdg-open "$CONSOLE_URL" >/dev/null 2>&1 & ) || true

echo "  Starte den Agent jetzt dauerhaft (Ctrl+C zum Beenden) ..."
sleep 1
rm -- "$0"
exec ./run_dev.sh
