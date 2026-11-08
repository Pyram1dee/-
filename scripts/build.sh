#!/usr/bin/env bash
# Компиляция всех src/*.sma установленным компилятором AMXX.
# Ожидает AMX Mod X 1.9 в vendor/amxmodx (addons/amxmodx/scripting).
# Include ZP 4.3 FIX (zombieplague.inc) кладётся в vendor/include/.
# Результат: build/plugins/*.amxx, лог: build/logs/build-<дата>.log
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTING="${AMXX_SCRIPTING:-$ROOT/vendor/amxmodx/addons/amxmodx/scripting}"
AMXXPC="$SCRIPTING/amxxpc"
OUT="$ROOT/build/plugins"
LOGDIR="$ROOT/build/logs"
LOG="$LOGDIR/build-$(date +%Y%m%d-%H%M%S).log"

if [[ ! -x "$AMXXPC" ]]; then
  echo "ОШИБКА: компилятор не найден: $AMXXPC" >&2
  echo "См. docs/ENVIRONMENT.md, раздел 'Получение зависимостей'." >&2
  exit 2
fi

mkdir -p "$OUT" "$LOGDIR"
INC=(-i"$SCRIPTING/include")
[[ -d "$ROOT/vendor/include" ]] && INC+=(-i"$ROOT/vendor/include")
[[ -d "$ROOT/src/include" ]] && INC+=(-i"$ROOT/src/include")

fail=0
shopt -s nullglob
files=("$ROOT"/src/*.sma)
[[ $# -gt 0 ]] && files=("$@")
for sma in "${files[@]}"; do
  name="$(basename "$sma" .sma)"
  echo "== $name" | tee -a "$LOG"
  if "$AMXXPC" "${INC[@]}" -o"$OUT/$name.amxx" "$sma" >>"$LOG" 2>&1; then
    echo "   OK" | tee -a "$LOG"
  else
    echo "   FAIL (см. $LOG)" | tee -a "$LOG"
    fail=1
  fi
done
echo "Лог: $LOG"
exit $fail
