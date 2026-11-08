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

## Локальные замены (не в git)
Файлы из `vendor/assets_override/<путь на сервере>` при `scripts/server.sh deploy` копируются поверх наших.
Проверка перед установкой: `python3 tools/mdl/check_model.py <файл.mdl> [--knife]`.

| Путь на сервере | Источник | Проверка | Лицензия |
|---|---|---|---|
| `models/cso/v_hammer.mdl` | архив пользователя `hammer.zip` (`hammer/v_knife.mdl`, ссылки на all-cs.ru), SHA-256 `1ea09e66c088a41359b34721d0314f3142d6c5ef624fd44cd4f2045d3d38d4a3` | OK: MDL v10, 8 последовательностей в порядке ножа CS, все кадры декодируются, текстуры ≤ 512 | **порт из Counter-Strike Online (Nexon)**: кость `CSO_hammer`, текстуры `CSO_*`. Разрешения правообладателя нет — в репозиторий и релизный ZIP не включается |
| `models/player/zombie_classic/zombie_classic.mdl` | архив пользователя `zombie_classic.rar` (2010 г., имя в заголовке `z2.mdl`), SHA-256 `99caa25a7e4fe93b5e24ff6f53b524975ba908efb6c4d68bad82e57f9204969e` | OK: модель игрока CS, 111 последовательностей в том же порядке, что `zombie_source.mdl`, скелет Bip01, 21 хитбокс, все кадры декодируются | происхождение и лицензия **неизвестны** (текстуры `zombie2_*`) — в репозиторий и релиз не включается |

С заменой у VIP от первого лица двуручный CSO-молот, а у других игроков — наш `p_hammer.mdl` (в архиве нет p_-модели).

Модель класса назначается в `config/zclass_models.cfg` (сейчас: `Classic Zombie = zombie_classic`). `scripts/apply_zclass_models.py`
при деплое меняет строку `MODELS` в `zp_zombieclasses.ini` только если файл модели есть на сервере — ZP 4.3 кэширует
модель класса без проверки, и отсутствующий файл роняет сервер при загрузке карты.

### Поставка 2026-11-08 (архивы пользователя)

| Что | Куда на сервере | Статус | Происхождение / лицензия |
|---|---|---|---|
| Poison Launcher 1.8.1 (`9778_-_amxx_public_poison_launcher_1.8.1.rar`, SHA-256 `fa99b943…0d02`) | `models/zm/*`, `sound/weapons/plaunch*`, `sprites/poison_*.spr` + плагин `cso_poison_launcher.amxx` | **подключён** (исходник адаптирован патчем, см. ниже) | плагин Re.Act!ve, лицензия не указана; модели/спрайты в стиле CSO — не в git |
| David Black (`terror.mdl`) | `models/player/cso_davidblack/cso_davidblack.mdl` | **подключён** как модель людей | неизвестно — не в git |
| Carlito (`guerilla.mdl`, внутри `mercenarytr.mdl`) | `models/player/cso_carlito/cso_carlito.mdl` | **подключён** как модель людей | неизвестно — не в git |
| Alice (`ma_alice_blue.mdl`) | `models/player/cso_alice/cso_alice.mdl` | **подключён** как модель людей | неизвестно — не в git. `ma_alice_blueT.mdl` и `.tga` не нужны: текстуры внутри основного файла |
| Katana Gold CSO (`v_knife`/`p_knife`) | — | отложен в `vendor/assets_staged/katana_gold` | CSO (Nexon), ссылка dream-x.ru — не в git |
| aknife (`v_knife`, `p_aknife1`) | — | отложен в `vendor/assets_staged/aknife` | анимации `Nexon_CSO_*` — CSO (Nexon) |
| Golden M4A1 (`v_m4a1.mdl`) | — | отложен в `vendor/assets_staged/golden_m4a1` | помечен «[NO CSO]», автор неизвестен |
| `heavy_zombie.zip` | — | **не подходит** | Source/CS:GO, MDL версии 49 (+ .vvd/.vtx/.vtf) — GoldSrc не загружает |
| `cso_dual_infinity_skin` | — | **не подходит** | Source/CS:S, MDL версии 44 |

Модели людей назначаются строкой `HUMAN` в `zombieplague.ini` по `config/human_models.cfg` — только присутствующие на сервере.
Отложенные модели: подмена стандартных `v_knife.mdl`/`v_m4a1.mdl` на сервере клиентам не скачивается,
нужен плагин, выставляющий свою модель по уникальному пути — решение за владельцем (см. DECISIONS).
