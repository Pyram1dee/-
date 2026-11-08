# Окружение (этап 0 — аудит)

Дата аудита: 2026-11-08. Среда: облачный контейнер Claude Code, Ubuntu 24.04.5 LTS, x86_64, Python 3.13, GCC 13.3.

## Найдено / проверено

| Компонент | Статус | Детали |
|---|---|---|
| Структура проекта | OK | `python3 scripts/check_project.py` → `Project scaffold OK` |
| AMX Mod X 1.9 (base + cstrike, Linux) | Скачан, **не запускался** | `https://www.amxmodx.org/amxxdrop/1.9/amxmodx-1.9.0-git5303-{base,cstrike}-linux.tar.gz` (ссылка, на которую ведёт `latest.php?version=1.9&os=linux`) |
| SHA-256 base | — | `1ed6898ced2c1fcf225c288b94effc19917e987b284e42911587738ee3c93699` |
| SHA-256 cstrike | — | `a2a5ef44bb366a90adf432c708ac49eb63b4b44d7b0de123e8cd52395d27b8e9` |
| Компилятор `amxxpc` | Есть в архиве, **запуск запрещён** | ELF 32-bit i386. 32-битные библиотеки (`libc6:i386`, `libstdc++6:i386`) установлены через apt. Права сессии не дают запускать скачанный бинарник ("Code from External") — нужно разрешение пользователя |
| Include AMXX (`amxmodx`, `fakemeta`, `hamsandwich`, `cstrike`, `fun`, `engine`) | Есть в архиве | `addons/amxmodx/scripting/include` |
| ZP 4.3 FIX (`zombie_plague40.sma`, `zombieplague.inc`) | **Отсутствует** | forums.alliedmods.net отвечает 403 через прокси среды. Нужно предоставить файл в `vendor/` |
| HLDS / ReHLDS (cstrike) | **Отсутствует** | SteamCMD (`media.steampowered.com`) доступен по сети, но запуск SteamCMD/HLDS — тоже запуск внешних бинарников, требует разрешения |
| Metamod / Metamod-r | **Отсутствует** | — |
| Poison Launcher 1.8.1 (`9778_-_amxx_public_poison_launcher_1.8.1.rar`) | **Отсутствует** | Пользовательский архив, нужен в `vendor/` |
| heavy_zombie.zip | **Отсутствует** | Source-форматы, всё равно требуют замены на GoldSrc |

Версии HLDS/Metamod/ZP сознательно не указаны — они не проверены.

## Получение зависимостей

Все сторонние файлы кладутся в `vendor/` (в `.gitignore`, не коммитятся):

```
vendor/
  amxmodx/addons/amxmodx/...      # распакованные amxmodx-1.9.0-git5303-base-linux + cstrike-linux
  include/zombieplague.inc        # из оригинального ZP 4.3 FIX
  zp43fix/                        # исходник zombie_plague40.sma + ресурсы ZP
  poison_launcher/                # распакованный архив пользователя
```

1. AMXX: `tar xzf amxmodx-1.9.0-git5303-base-linux.tar.gz -C vendor/amxmodx` (то же для cstrike).
2. ZP 4.3 FIX: ветка "Zombie Plague 4.3 Fix" на forums.alliedmods.net (оригинальный автор MeRcyLeZZ). Не ZA.RU, не REZP.
3. HLDS: `steamcmd +force_install_dir ./hlds +login anonymous +app_set_config 90 mod cstrike +app_update 90 validate +quit`.
4. Metamod: версия, совместимая с выбранной сборкой HLDS (зафиксировать после установки).

## Процесс проверки

- Компиляция: `scripts/build.sh` → `build/plugins/*.amxx`, лог `build/logs/build-*.log`. Без компилятора скрипт завершается с кодом 2 и понятным сообщением (проверено).
- Runtime: HLDS `+map de_dust2`, затем `amxx plugins`, `say /cso`, логи в `cstrike/addons/amxmodx/logs/`.

## Блокеры (на 2026-11-08)

1. Нет разрешения запускать `amxxpc` → ни один `.sma` не скомпилирован.
2. Нет ZP 4.3 FIX → классы, магазин, Deimos Round и VIP Hammer (всё, что зависит от `zombieplague.inc`) по плану **не начинаются**.
3. Нет HLDS → этап 1 (запуск сервера) не выполнен.
