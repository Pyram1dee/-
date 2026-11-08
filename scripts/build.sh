#!/usr/bin/env bash
# Компиляция всех source/*.sma установленным компилятором AMXX.
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
fail=0
INC=(-i"$SCRIPTING/include")
[[ -d "$ROOT/vendor/include" ]] && INC+=(-i"$ROOT/vendor/include")
[[ -d "$ROOT/source/include" ]] && INC+=(-i"$ROOT/source/include")

shopt -s nullglob
files=("$ROOT"/source/*.sma)
if [[ $# -gt 0 ]]; then
  files=("$@")
else
  # сторонние плагины: адаптируются патчами tools/thirdparty, исходники авторов не в git
  for pair in "poison_launcher:cso_poison_launcher" "jetpack:cso_jetpack"; do
    vdir="${pair%%:*}"; out="${pair#*:}"
    [[ -d "$ROOT/vendor/$vdir" ]] || continue
    if python3 -I "$ROOT/tools/thirdparty/patch_${vdir}.py" | tee -a "$LOG"; then
      files+=("$ROOT/build/thirdparty/$out.sma")
    else
      echo "   FAIL: патч $vdir не применился" | tee -a "$LOG"
      fail=1
    fi
  done
fi
for sma in "${files[@]}"; do
  name="$(basename "$sma" .sma)"
  echo "== $name" | tee -a "$LOG"
  sma="$(cd "$(dirname "$sma")" && pwd)/$(basename "$sma")"
  if (cd "$SCRIPTING" && ./amxxpc "${INC[@]}" -o"$OUT/$name.amxx" "$sma") >>"$LOG" 2>&1; then
    echo "   OK" | tee -a "$LOG"
  else
    echo "   FAIL (см. $LOG)" | tee -a "$LOG"
    fail=1
  fi
done
echo "Лог: $LOG"
exit $fail
