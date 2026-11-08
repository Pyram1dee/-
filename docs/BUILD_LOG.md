# Журнал сборок

| Дата | Этап | Модуль | Результат |
|---|---|---|---|
| 2026-11-08 | 0 | структура (`check_project.py`) | OK |
| 2026-11-08 | 0 | `scripts/build.sh` без компилятора | Код 2, "компилятор не найден" — ожидаемо |
| 2026-11-08 | 1 | `cso_core.sma` | НЕ СОБРАН: запуск `amxxpc` запрещён правами сессии |
| 2026-11-08 | 1 | `cso_core.sma` (1-я попытка) | FAIL: `amxxpc32.so: cannot open shared object` — компилятор нужно запускать из его папки; `build.sh` исправлен |
| 2026-11-08 | 1 | `cso_core.sma` | OK, 0 ошибок, 0 предупреждений, AMXX 1.9.0.5303, `build/plugins/cso_core.amxx` (1136 байт). Runtime на HLDS не проверялся |
| 2026-11-08 | 1 | ZP 4.3 Fix5a `zombie_plague40.sma` (из комплекта albinzm.com) | OK, 0 предупреждений — исходник ядра собирается нашим компилятором; используем собственную сборку, а не готовый `.amxx` из архива |
| 2026-11-08 | 1 | ZP `zp_zclasses40.sma`, примеры `zp_zombie_classes_example`, `zp_extra_items_example` | OK |
| 2026-11-08 | 2 | `cso_zclass_predator.sma` | OK, 0 предупреждений |
| 2026-11-08 | 2 | `cso_zclass_invisible.sma` | OK, 0 предупреждений |
| 2026-11-08 | 2 | `cso_zclass_undertaker.sma` | OK, 0 предупреждений |
| 2026-11-08 | 2 | `cso_zclass_shaman.sma` | OK, 0 предупреждений |
| 2026-11-08 | 2 | `cso_zclass_heavy.sma` | OK, 0 предупреждений |
| 2026-11-08 | 2 | `cso_zclass_nurse.sma` | OK, 0 предупреждений |
| 2026-11-08 | 2 | `cso_zclass_deimos.sma` | OK, 0 предупреждений |
| 2026-11-08 | 2 | Полная пересборка 8 плагинов | OK, 0 предупреждений. **Runtime не проверен** (нет HLDS), чек-лист `tests/TEST_CLASSES.md` не пройден |
| 2026-11-08 | 3 | `cso_deimos_round.sma` | OK, 0 предупреждений |
| 2026-11-08 | 3 | `cso_human_shop.sma` (1-я попытка) | FAIL: `menu_items` конфликтует с native AMXX — колбэки переименованы |
| 2026-11-08 | 3 | `cso_human_shop.sma` | OK, 0 предупреждений |
| 2026-11-08 | 3 | `tests/compile/test_shop_api.sma` (потребитель `cso_shop.inc`) | OK |
| 2026-11-08 | 3 | Poison Launcher adapter | НЕ НАЧАТ: нет архива `9778_-_amxx_public_poison_launcher_1.8.1.rar` |
| 2026-11-08 | 4 | `cso_vip_hammer.sma` | OK, 0 предупреждений |
| 2026-11-08 | 4 | Полная пересборка 11 плагинов | OK, 0 предупреждений |
| 2026-11-08 | 4 | `scripts/check_cvars.py` | OK: 58 CVAR в `cso_custom.cfg` совпадают с `register_cvar` |
| 2026-11-08 | 1 | `scripts/server.sh` | Написан, **не запускался** (нужно разрешение на запуск SteamCMD/HLDS). Сервер НЕ протестирован |
| 2026-11-08 | 5 | `tools/mdl/goldsrc_mdl.py` — парсер MDL v10 на эталонных моделях ZP (`v_knife_zombie`, `v_grenade_frost`, `zombie_source`) | OK: число треугольников из tri-команд совпадает с numtris, анимации всех последовательностей декодируются; найдены и исправлены 3 ошибки смещений в форматах |
| 2026-11-08 | 5 | `tools/mdl/build_models.py` → `coffin.mdl`, `zombitrap.mdl`, `v_hammer.mdl`, `p_hammer.mdl` | OK |
| 2026-11-08 | 5 | `tools/mdl/validate.py` | OK: воспроизводимость байт-в-байт, обход 100 % по часовой, ошибка анимации ≤ 0.016 юнита, габариты в bbox плагинов. Клиент CS 1.6 не запускался |
| 2026-11-08 | 5 | `cso_zclass_undertaker` (bbox 64, HULL_HUMAN), `cso_zclass_heavy`, `cso_vip_hammer` | OK, 0 предупреждений |
| 2026-11-08 | 5 | `v_hammer.mdl` пользователя (`hammer.zip`) через `tools/mdl/check_model.py --knife` | OK: формат, 8 анимаций ножа, все кадры, обход 100 %. Установлен как локальная замена, не в git. В клиенте не проверялся |
| 2026-11-08 | 5 | `zombie_classic.mdl` пользователя через `check_model.py` | OK: модель игрока, 111 последовательностей как у `zombie_source`, все кадры. Локальная замена, не в git. В клиенте не проверялась |
| 2026-11-08 | 5 | `scripts/apply_zclass_models.py` на копии `zp_zombieclasses.ini` | OK: без файла модели — без изменений; с файлом — меняется одна строка MODELS; повторный запуск идемпотентен; окончания строк сохранены |
| 2026-11-08 | 3 | Poison Launcher 1.8.1, оригинал | OK с 1 предупреждением (`client_disconnect` deprecated); не используется |
| 2026-11-08 | 3 | `cso_poison_launcher.sma` после патча (1-я попытка) | FAIL: `return` без `;` склеился с блоком — исправлено в патче |
| 2026-11-08 | 3 | `cso_poison_launcher.sma` после патча | OK, 0 предупреждений; все 13 precache-ресурсов есть в архиве/базовой CS |
| 2026-11-08 | 3 | `cso_human_shop.sma` (+ `cso_shop_register_item_cvar`) | OK, 0 предупреждений |
| 2026-11-08 | 5 | Модели пользователя: Poison Launcher (5), David Black, Carlito, Alice, катана, aknife, M4A1 через `check_model.py` | OK (spore.mdl — обратный обход, у автора так же); heavy_zombie и dual_infinity — формат Source, отклонены |
| 2026-11-08 | 5 | `apply_zclass_models.py` (HUMAN) на копии `zombieplague.ini` | OK: без файлов — без изменений, с 2 файлами — HUMAN из 2 моделей, повтор идемпотентен |
| 2026-11-08 | — | Полная пересборка (12 плагинов, включая Poison Launcher) | OK, 0 предупреждений. Runtime на HLDS не проверялся |
| 2026-11-08 | 3 | `cso_human_dodge.sma` (своя реализация вместо `zp_human_dodge`) | OK, 0 предупреждений. Runtime не проверялся |
| 2026-11-08 | 2 | `cso_zclass_undertaker.sma` 0.2.0 (механика Stamper) | OK, 0 предупреждений. Runtime не проверялся |
| 2026-11-08 | 5 | `apply_zclass_models.py` + CLAWMODEL на копии ini | OK: без файла когтей — без изменений, с файлом — меняется строка CLAWMODEL |
| 2026-11-08 | 3 | Jetpack+Bazooka 3.2 (pastebin), оригинал | OK с 1 предупреждением (`client_disconnect`); не используется |
| 2026-11-08 | 3 | `cso_jetpack.sma` после патча | OK, 0 предупреждений |
| 2026-11-08 | — | Полная пересборка (14 плагинов) | OK, 0 предупреждений; CVAR 75/75. Runtime не проверялся |
