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
