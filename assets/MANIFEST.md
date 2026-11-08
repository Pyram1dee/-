# Манифест ресурсов

Ресурсы в репозиторий не коммитятся (CLAUDE.md п. 5). Если файла нет — плагин пишет предупреждение в лог AMXX и использует указанный запасной вариант.

| Путь на сервере | Кто использует | Есть сейчас | Запасной вариант | Примечание |
|---|---|---|---|---|
| `models/player/zombie_source/zombie_source.mdl` | все классы (модель игрока) | да, комплект ZP 4.3 Fix5a | — | заменить своими GoldSrc-моделями классов, затем поменять `ZC_MODEL` |
| `models/zombie_plague/v_knife_zombie.mdl` | все классы (когти) | да, ZP | — | |
| `models/cso/coffin.mdl` | Undertaker | **нет** | `models/w_weaponbox.mdl` (CS 1.6) | хитбокс гроба фиксирован 32×32×36 |
| `models/cso/zombitrap.mdl` | Heavy | **нет** | `models/w_weaponbox.mdl` | `heavy_zombie.zip` — Source-формат, не подходит |
| `models/cso/v_hammer.mdl`, `models/cso/p_hammer.mdl` | VIP Hammer | **нет** | обычный нож | |
| `sprites/laserbeam.spr` | Deimos | да, CS 1.6 | — | |
| `sound/zombie_plague/zombie_madness1.wav` | Shaman | да, ZP | — | |

Все `.mdl` проверять на формат GoldSrc (заголовок `IDST`, версия 10) и регистр имён на Linux.
