#!/usr/bin/env bash
# Установка и smoke-запуск тестового HLDS (Counter-Strike 1.6) с ZP 4.3 Fix5a и модулями CSO.
#
#   ./scripts/server.sh install            — SteamCMD + HLDS (app 90, cstrike) + Metamod-P + AMXX + ZP + наши плагины
#   ./scripts/server.sh deploy             — только пересобрать и переложить плагины/конфиги
#   ./scripts/server.sh smoke [map] [sec]  — запустить сервер, выполнить amxx/meta команды, остановить; лог в build/logs/
#
# Всё ставится в vendor/ (в .gitignore). Версии фиксируются в docs/ENVIRONMENT.md после установки.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor"
HLDS="$VENDOR/hlds"
CS="$HLDS/cstrike"
LOGDIR="$ROOT/build/logs"
STEAMCMD_URL="https://media.steampowered.com/installer/steamcmd_linux.tar.gz"
METAMOD_URL="https://downloads.sourceforge.net/project/metamod-p/Metamod-P%20Binaries/1.21p37/metamod-p-1.21p37-linux_i686.tar.gz"
ZP_DIR="$VENDOR/zp43fix5a"
mkdir -p "$LOGDIR"

log() { echo "[server.sh] $*"; }

install_hlds() {
  mkdir -p "$VENDOR/steamcmd"
  if [[ ! -x "$VENDOR/steamcmd/steamcmd.sh" ]]; then
    log "Скачиваю SteamCMD"
    curl -sSL "$STEAMCMD_URL" | tar xz -C "$VENDOR/steamcmd"
  fi
  # app 90 часто требует несколько попыток
  for i in 1 2 3 4; do
    log "SteamCMD: app_update 90 (попытка $i)"
    if "$VENDOR/steamcmd/steamcmd.sh" +force_install_dir "$HLDS" +login anonymous \
         +app_set_config 90 mod cstrike +app_update 90 validate +quit; then
      [[ -f "$HLDS/hlds_linux" && -d "$CS" ]] && break
    fi
  done
  [[ -f "$HLDS/hlds_linux" ]] || { log "ОШИБКА: HLDS не установлен"; exit 3; }
  # steamclient.so для запуска
  mkdir -p "$HOME/.steam/sdk32"
  cp -f "$VENDOR/steamcmd/linux32/steamclient.so" "$HOME/.steam/sdk32/" 2>/dev/null || true
}

install_metamod() {
  local dst="$CS/addons/metamod/dlls"
  mkdir -p "$dst" "$VENDOR/metamod"
  if [[ ! -f "$VENDOR/metamod/metamod.tgz" ]]; then
    log "Скачиваю Metamod-P 1.21p37"
    curl -sSL -o "$VENDOR/metamod/metamod.tgz" "$METAMOD_URL"
  fi
  tar xzf "$VENDOR/metamod/metamod.tgz" -C "$VENDOR/metamod"
  local so
  so="$(find "$VENDOR/metamod" -name '*.so' | head -1)"
  [[ -n "$so" ]] || { log "ОШИБКА: в архиве Metamod нет .so"; exit 3; }
  cp -f "$so" "$dst/metamod_i386.so"
  sed -i 's|^gamedll_linux.*|gamedll_linux "addons/metamod/dlls/metamod_i386.so"|' "$CS/liblist.gam"
  echo 'linux addons/amxmodx/dlls/amxmodx_mm_i386.so' > "$CS/addons/metamod/plugins.ini"
}

install_amxx_zp() {
  [[ -d "$VENDOR/amxmodx/addons" ]] || { log "ОШИБКА: нет vendor/amxmodx (docs/ENVIRONMENT.md)"; exit 3; }
  [[ -d "$ZP_DIR/addons" ]] || { log "ОШИБКА: нет vendor/zp43fix5a"; exit 3; }
  cp -rf "$VENDOR/amxmodx/addons" "$CS/"
  # ресурсы и конфиги ZP (готовые .amxx из архива НЕ используем — ставим собранные нами)
  cp -rf "$ZP_DIR/models" "$ZP_DIR/sound" "$CS/"
  [[ -d "$ZP_DIR/sprites" ]] && cp -rf "$ZP_DIR/sprites" "$CS/"
  cp -f "$ZP_DIR"/addons/amxmodx/configs/* "$CS/addons/amxmodx/configs/"
  cp -f "$ZP_DIR"/addons/amxmodx/data/lang/* "$CS/addons/amxmodx/data/lang/"
}

deploy_plugins() {
  log "Сборка ZP и модулей"
  local zps="$ZP_DIR/addons/amxmodx/scripting"
  "$ROOT/scripts/build.sh" "$zps/zombie_plague40.sma" "$zps/zp_zclasses40.sma" "$ROOT"/src/*.sma
  cp -f "$ROOT"/build/plugins/*.amxx "$CS/addons/amxmodx/plugins/"

  # Модули CSO грузятся ПОСЛЕ ядра ZP: дописываем их в plugins-zplague.ini
  local ini="$CS/addons/amxmodx/configs/plugins-zplague.ini"
  cp -f "$ZP_DIR/addons/amxmodx/configs/plugins-zplague.ini" "$ini"
  { echo; echo "; --- CSO Custom Edition (config/plugins-cso.ini)"; grep -vE '^\s*(;|$)' "$ROOT/config/plugins-cso.ini" | sed 's/$/ debug/'; } >> "$ini"

  # собственные модели проекта
  mkdir -p "$CS/models/cso"
  cp -f "$ROOT"/assets/models/cso/*.mdl "$CS/models/cso/"
  # локальные замены пользователя (не в git): vendor/assets_override/<путь на сервере>
  if [[ -d "$VENDOR/assets_override" ]]; then
    log "Локальные замены ресурсов из vendor/assets_override:"
    (cd "$VENDOR/assets_override" && find . -type f -print) | sed 's/^/  /'
    cp -rf "$VENDOR/assets_override/." "$CS/"
  fi

  cp -f "$ROOT/config/cso_custom.cfg" "$CS/addons/amxmodx/configs/"
  local amxxcfg="$CS/addons/amxmodx/configs/amxx.cfg"
  grep -q 'cso_custom.cfg' "$amxxcfg" || echo 'exec addons/amxmodx/configs/cso_custom.cfg' >> "$amxxcfg"

  # Ускорение Хищника упирается в sv_maxspeed (по умолчанию 320)
  touch "$CS/server.cfg"
  grep -q '^sv_maxspeed' "$CS/server.cfg" || echo 'sv_maxspeed 400' >> "$CS/server.cfg"
}

smoke() {
  local map="${1:-de_dust2}" secs="${2:-25}"
  local log="$LOGDIR/server-$(date +%Y%m%d-%H%M%S).log"
  [[ -f "$HLDS/hlds_linux" ]] || { log "ОШИБКА: HLDS не установлен, сначала install"; exit 3; }
  log "Smoke: карта $map, $secs с, лог $log"
  (
    sleep "$secs"
    echo "meta list"; sleep 1
    echo "amxx plugins"; sleep 1
    echo "amxx modules"; sleep 1
    echo "zp_version"; sleep 1
    echo "cso_custom_version"; sleep 1
    echo "changelevel $map"; sleep 10
    echo "amxx plugins"; sleep 1
    echo "quit"
  ) | (cd "$HLDS" && LD_LIBRARY_PATH=".:${LD_LIBRARY_PATH:-}" timeout $((secs + 40)) ./hlds_linux \
        -game cstrike -console -insecure +sv_lan 1 +maxplayers 12 -port 27015 +map "$map" 2>&1) | tee "$log" || true
  log "Ошибки в логе сервера:"
  grep -niE 'error|fail|bad load|unknown|crash|segmentation' "$log" || echo "  (не найдено)"
  log "Логи AMXX: $CS/addons/amxmodx/logs/"
}

case "${1:-}" in
  install) install_hlds; install_metamod; install_amxx_zp; deploy_plugins ;;
  deploy)  deploy_plugins ;;
  smoke)   shift; smoke "$@" ;;
  *) echo "Использование: $0 install | deploy | smoke [map] [sec]"; exit 1 ;;
esac
