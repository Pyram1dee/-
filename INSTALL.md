# Установка CSO Zombie 1.6 — Custom Edition

> Сервер ещё **не запускался** в среде разработки: код компилируется, но работа в игре не подтверждена (см. `tests/`).

## Требования
- Linux-сервер Counter-Strike 1.6 (HLDS, app 90, mod cstrike) и Metamod (проект собирается с Metamod-P 1.21p37).
- AMX Mod X 1.9 (git5303) — base + cstrike.
- Zombie Plague 4.3 Fix5a — исходник `zombie_plague40.sma`, конфиги, ресурсы (см. `docs/ENVIRONMENT.md`).
- Python 3 (для скриптов сборки и проверки).

## Автоматически (рекомендуется)
```
vendor/amxmodx/          # распакованные amxmodx-1.9.0-git5303-{base,cstrike}-linux
vendor/zp43fix5a/        # комплект ZP 4.3 Fix5a
vendor/include/zombieplague.inc
vendor/poison_launcher/  # архив Poison Launcher 1.8.1 (необязательно)
vendor/jetpack/          # исходник Jetpack+Bazooka 3.2 (необязательно)
vendor/assets_override/  # ваши модели/звуки по путям сервера (необязательно)
```
```
./scripts/build.sh                 # компиляция всех модулей и адаптированных сторонних плагинов
./scripts/server.sh install        # SteamCMD + HLDS + Metamod-P + AMXX + ZP + модули + ресурсы
./scripts/server.sh smoke de_dust2 25   # пробный запуск, лог в build/logs/
```

## Вручную на готовый HLDS + Metamod + AMXX
1. Скопировать `build/plugins/*.amxx` в `cstrike/addons/amxmodx/plugins/` (включая собранный нами `zombie_plague40.amxx`).
2. Ресурсы ZP (`models/ sound/ sprites/`), `assets/models/cso/*.mdl` → `cstrike/models/cso/`, ресурсы из `vendor/` (если есть).
3. `configs/plugins-zplague.ini` из ZP; **в конец** дописать содержимое `config/plugins-cso.ini`; закомментировать `zp_zclasses40.amxx`.
4. В `configs/` положить `cso_custom.cfg`, `cso_knives.ini`, `cso_player_models.ini`; в `amxx.cfg` добавить
   `exec addons/amxmodx/configs/cso_custom.cfg` и `amx_language "ru"`.
5. `server.cfg`: `sv_maxspeed 400` (ускорение Хищника), `sv_allowdownload 1`.
6. Права: в `users.ini` флаг `t` — VIP, `s` — Gold (меняется `cso_vip_flag` / `cso_gold_flag`).
7. Модели классов и людей: `config/zclass_models.cfg`, `config/human_models.cfg` применяет `scripts/apply_zclass_models.py <cstrike>`
   (только для файлов, которые есть на сервере).

## Обновление
1. `git pull`, затем `./scripts/build.sh` (сборка без предупреждений обязательна).
2. `python3 scripts/check_cvars.py` и `python3 tools/mdl/validate.py` — без ошибок.
3. `./scripts/server.sh deploy` — перекладывает плагины, конфиги и ресурсы, не трогая HLDS.
4. Пройти чек-листы `tests/`.

## Команды игрока
`/menu` (или бинд `cso_menu`), `/guns`, `/shop`, `/vip`, `/gold`, `/models`; способность — `bind g cso_skill` или G/E/R;
рывок — двойное W; джетпак (VIP) — прыжок+присед в воздухе, ракета — нож + ПКМ.
