# Манифест ресурсов

Ресурсы в репозиторий не коммитятся (CLAUDE.md п. 5). Если файла нет — плагин пишет предупреждение в лог AMXX и использует указанный запасной вариант.

| Путь на сервере | Кто использует | Есть сейчас | Запасной вариант | Примечание |
|---|---|---|---|---|
| `models/player/zombie_source/zombie_source.mdl` | все классы (модель игрока) | да, комплект ZP 4.3 Fix5a | — | заменить своими GoldSrc-моделями классов, затем поменять `ZC_MODEL` |
| `models/zombie_plague/v_knife_zombie.mdl` | все классы (когти) | да, ZP | — | |
| `models/cso/coffin.mdl` | Undertaker | **да, собственная** | `models/w_weaponbox.mdl` (CS 1.6) | стоячий гроб 30×14×64, bbox сущности 32×32×64 |
| `models/cso/zombitrap.mdl` | Heavy | **да, собственная** | `models/w_weaponbox.mdl` | капкан d=30, h=9 |
| `models/cso/v_hammer.mdl`, `models/cso/p_hammer.mdl` | VIP Hammer | **да, собственные** | обычный нож | v_: 8 последовательностей в порядке ножа CS; p_: кость `Bip01 R Hand` |
| `sprites/laserbeam.spr` | Deimos | да, CS 1.6 | — | |
| `sound/zombie_plague/zombie_madness1.wav` | Shaman | да, ZP | — | |

Все `.mdl` проверять на формат GoldSrc (заголовок `IDST`, версия 10) и регистр имён на Linux.

## Собственные модели (`assets/models/cso`)
Геометрия и текстуры созданы генератором `tools/mdl/build_models.py` (Python, без сторонних ресурсов и без studiomdl),
лицензия — как у проекта. Пересборка: `python3 tools/mdl/build_models.py`; проверка: `python3 tools/mdl/validate.py`;
превью: `docs/models_preview.png`, `python3 tools/mdl/render.py <mdl> <png>`.

Проверено без клиента: формат MDL v10 (парсер сверен на моделях ZP), порядок обхода треугольников,
декодирование анимации алгоритмом движка, габариты. **Отрисовка в настоящем клиенте CS 1.6 не проверялась.**
