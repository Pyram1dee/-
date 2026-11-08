"""Сборка готового к установке архива: содержимое распаковывается в папку cstrike сервера.

  ./scripts/build.sh && ./scripts/build.sh vendor/zp43fix5a/addons/amxmodx/scripting/zombie_plague40.sma
  python3 scripts/package.py

Результат: build/release/CSO_Zombie_Custom_cstrike.zip (+ отчёт PACKAGE_REPORT.txt внутри).
Архив содержит сторонние ресурсы из vendor/ (ZP, AMXX, Metamod-P, присланные модели) —
он для сервера владельца и не публикуется (CLAUDE.md п. 5); в git попадает только этот скрипт.
"""
import re
import shutil
import sys
import tarfile
import zipfile
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
V = ROOT / "vendor"
OUT = ROOT / "build" / "release"
CS = OUT / "cstrike"
ZP = V / "zp43fix5a"
DL = V / "dl"

# Ресурсы, которые есть в любой установке CS 1.6 / Half-Life (папки cstrike/valve клиента и сервера)
BASE_GAME = {
    "models/w_weaponbox.mdl", "models/w_m3.mdl", "models/v_knife.mdl", "models/p_knife.mdl",
    "models/v_egon.mdl", "models/p_egon.mdl", "models/w_egon.mdl", "models/rpgrocket.mdl",
    "sprites/laserbeam.spr", "sprites/zerogxplode.spr", "sprites/shockwave.spr", "sprites/smoke.spr",
    "sprites/xfireball3.spr", "sprites/white.spr",
    "sound/weapons/explode3.wav", "sound/weapons/rocketfire1.wav", "sound/items/9mmclip2.wav",
    # стандартные звуки ножа CS (джетпак лишь сравнивает их имена в фильтре звуков)
    "sound/weapons/knife_deploy1.wav", "sound/weapons/knife_hit1.wav", "sound/weapons/knife_hit2.wav",
    "sound/weapons/knife_hit3.wav", "sound/weapons/knife_hit4.wav", "sound/weapons/knife_hitwall1.wav",
    "sound/weapons/knife_slash1.wav", "sound/weapons/knife_slash2.wav", "sound/weapons/knife_stab.wav",
}


def log(msg):
    print(f"[package] {msg}")


def copytree(src, dst):
    if src.exists():
        shutil.copytree(src, dst, dirs_exist_ok=True)


def need(path, what):
    if not path.exists():
        sys.exit(f"[package] ОШИБКА: нет {path} ({what})")


def main():
    plugins = ROOT / "build" / "plugins"
    need(plugins / "zombie_plague40.amxx", "соберите ядро ZP: ./scripts/build.sh vendor/zp43fix5a/.../zombie_plague40.sma")
    need(plugins / "cso_main_menu.amxx", "соберите модули: ./scripts/build.sh")
    need(V / "amxmodx" / "addons", "AMXX 1.9 Linux")

    if OUT.exists():
        shutil.rmtree(OUT)
    CS.mkdir(parents=True)
    amxx = CS / "addons" / "amxmodx"

    # 1. AMX Mod X 1.9: Linux + Windows (без компилятора)
    copytree(V / "amxmodx" / "addons", CS / "addons")
    for z in ("amxmodx-1.9.0-git5303-base-windows.zip", "amxmodx-1.9.0-git5303-cstrike-windows.zip"):
        if (DL / z).exists():
            with zipfile.ZipFile(DL / z) as zf:
                zf.extractall(CS)
        else:
            log(f"нет {z} — архив будет только для Linux")
    shutil.rmtree(amxx / "scripting", ignore_errors=True)
    (amxx / "scripting" / "cso").mkdir(parents=True)
    for f in (ROOT / "source").glob("*.sma"):
        shutil.copy2(f, amxx / "scripting" / "cso" / f.name)
    copytree(ROOT / "source" / "include", amxx / "scripting" / "cso" / "include")

    # 2. Metamod-P 1.21p37
    mm = CS / "addons" / "metamod" / "dlls"
    mm.mkdir(parents=True)
    if (DL / "metamod-p-1.21p37-linux_i686.tar.gz").exists():
        with tarfile.open(DL / "metamod-p-1.21p37-linux_i686.tar.gz") as tf:
            m = tf.extractfile("metamod.so")
            (mm / "metamod.so").write_bytes(m.read())
    if (DL / "metamod-p-1.21p37-windows.zip").exists():
        with zipfile.ZipFile(DL / "metamod-p-1.21p37-windows.zip") as zf:
            (mm / "metamod.dll").write_bytes(zf.read("metamod.dll"))
    (CS / "addons" / "metamod" / "plugins.ini").write_text(
        "win32 addons\\amxmodx\\dlls\\amxmodx_mm.dll\nlinux addons/amxmodx/dlls/amxmodx_mm_i386.so\n")

    # 3. Zombie Plague 4.3 Fix5a: конфиги, языки, ресурсы (плагин — наша сборка)
    for f in (ZP / "addons" / "amxmodx" / "configs").iterdir():
        shutil.copy2(f, amxx / "configs" / f.name)
    copytree(ZP / "addons" / "amxmodx" / "data" / "lang", amxx / "data" / "lang")
    for d in ("models", "sound", "sprites"):
        copytree(ZP / d, CS / d)

    # 4. Плагины: ядро ZP + модули CSO (+ адаптированные сторонние)
    (amxx / "plugins").mkdir(exist_ok=True)
    for f in plugins.glob("*.amxx"):
        if f.name.startswith("zp_zclasses40") or f.name.startswith("test_"):
            continue
        shutil.copy2(f, amxx / "plugins" / f.name)

    # plugins-zplague.ini: ядро ZP, затем модули CSO (после ядра); стандартные классы ZP выключены
    ini = amxx / "configs" / "plugins-zplague.ini"
    text = ini.read_text(encoding="utf-8", errors="replace").replace("\nzp_zclasses40.amxx", "\n;zp_zclasses40.amxx")
    lines = []
    for ln in (ROOT / "config" / "plugins-cso.ini").read_text(encoding="utf-8").splitlines():
        ln = ln.split(";", 1)[0].strip()
        if ln:
            if not (amxx / "plugins" / ln).exists():
                log(f"нет {ln} — пропущен в plugins-zplague.ini")
                continue
            lines.append(f"{ln} debug")
    ini.write_text(text.rstrip() + "\n\n; --- CSO Custom Edition\n" + "\n".join(lines) + "\n", encoding="utf-8")

    # 5. Конфиги CSO
    cfg = (ROOT / "config" / "cso_custom.cfg").read_text(encoding="utf-8")
    cfg += "\n// --- сервер (из пакета)\nsv_maxspeed 400        // ускорение Хищника и ножей\nsv_allowdownload 1     // игроки скачивают модели\n"
    (amxx / "configs" / "cso_custom.cfg").write_text(cfg, encoding="utf-8")
    for f in ("cso_knives.ini", "cso_player_models.ini"):
        shutil.copy2(ROOT / "config" / f, amxx / "configs" / f)
    amxxcfg = amxx / "configs" / "amxx.cfg"
    t = amxxcfg.read_text(encoding="utf-8", errors="replace")
    t = re.sub(r'(?m)^amx_language.*$', 'amx_language "ru"', t)
    if 'amx_language "ru"' not in t:
        t += '\namx_language "ru"\n'
    t += "\n// CSO Zombie Custom Edition\nexec addons/amxmodx/configs/cso_custom.cfg\n"
    amxxcfg.write_text(t, encoding="utf-8")

    # 6. Ресурсы CSO: собственные модели, Poison Launcher, локальные замены пользователя
    copytree(ROOT / "assets" / "models" / "cso", CS / "models" / "cso")
    pl = V / "poison_launcher" / "cstrike"
    for d in ("models", "sound", "sprites"):
        copytree(pl / d, CS / d)
    ov = V / "assets_override"
    if ov.exists():
        for f in ov.rglob("*"):
            if f.is_file() and "zombie_classic" not in f.parts:  # класс-владелец отключён по ТЗ
                dst = CS / f.relative_to(ov)
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(f, dst)

    # 7. Модели людей в zombieplague.ini (только присутствующие файлы)
    sys.path.insert(0, str(ROOT / "scripts"))
    import apply_zclass_models as azm  # noqa: E402
    azm.apply_human_models(CS)

    # 8. Проверка: каждый precache-ресурс плагинов есть в пакете или в базовой игре
    missing = []
    sources = list((ROOT / "source").glob("*.sma")) + list((ROOT / "source" / "include").glob("*.inc")) \
        + list((ROOT / "build" / "thirdparty").glob("*.sma"))
    found = set()
    for f in sources:
        t = f.read_text(encoding="utf-8")
        for m in re.finditer(r'"((?:models|sprites)/[^"%]+\.(?:mdl|spr))"|"((?:zombie_plague|weapons|items)/[^"%]+\.wav)"', t):
            found.add(m.group(1) or "sound/" + m.group(2))
    for line in (amxx / "configs" / "cso_knives.ini").read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.startswith(";") and "=" in line:
            for p in line.split("=", 1)[1].split(","):
                if p.strip():
                    found.add(p.strip())
    for p in sorted(found):
        if not (CS / p).exists() and p not in BASE_GAME:
            missing.append(p)

    # 9. Инструкция и отчёт
    readme = (ROOT / "build" / "release_README_RU.txt")
    readme.write_text(README.format(date=date.today().isoformat(), plugins=len(list((amxx / "plugins").glob("cso_*.amxx")))), encoding="utf-8")
    shutil.copy2(readme, OUT / "README_RU.txt")
    report = [f"Пакет собран {date.today().isoformat()}", f"Плагинов: {len(list((amxx / 'plugins').glob('*.amxx')))}",
              "Статус: компиляция без ошибок и предупреждений; НА HLDS НЕ ЗАПУСКАЛОСЬ.", ""]
    report.append("Недостающие precache-ресурсы: " + (", ".join(missing) if missing else "нет"))
    report.append("Недостающие позиции и модели: см. docs/MISSING_RESOURCES.md в репозитории.")
    (OUT / "PACKAGE_REPORT.txt").write_text("\n".join(report) + "\n", encoding="utf-8")
    shutil.copytree(ROOT / "tests", OUT / "tests")
    # Windows: запуск в консольном режиме (без -console hlds.exe требует AdminServer.dll)
    (OUT / "start_server.bat").write_bytes(
        b"@echo off\r\ncd /d \"%~dp0\"\r\n"
        b"hlds.exe -console -game cstrike +sv_lan 1 +maxplayers 20 +map de_dust2\r\npause\r\n")

    zpath = OUT / "CSO_Zombie_Custom_cstrike.zip"
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in sorted(OUT.rglob("*")):
            if f.is_file() and f != zpath:
                zf.write(f, f.relative_to(OUT))
    log(f"готово: {zpath} ({zpath.stat().st_size // 1024} КБ)")
    if missing:
        log("ВНИМАНИЕ, нет ресурсов: " + ", ".join(missing))
        sys.exit(1)


README = """CSO Zombie 1.6 — Custom Edition. Пакет для установки ({date})
====================================================================

ВАЖНО: всё скомпилировано без ошибок, но на сервере ещё НЕ запускалось.
Первый запуск — тестовый: если в консоли или в addons/amxmodx/logs/ будут ошибки, пришлите их.

Что внутри (папка cstrike/):
  addons/metamod/            Metamod-P 1.21p37 (Linux metamod.so и Windows metamod.dll)
  addons/amxmodx/            AMX Mod X 1.9 (Linux и Windows), Zombie Plague 4.3 Fix5a и {plugins} плагинов CSO,
                             конфиги (cso_custom.cfg, cso_knives.ini, cso_player_models.ini),
                             исходники в addons/amxmodx/scripting/cso/
  models/ sound/ sprites/    ресурсы ZP, Poison Launcher, модели ножей/молота/гроба/капкана, модели людей

УСТАНОВКА
1. Нужен чистый сервер Counter-Strike 1.6 (HLDS). Сделайте резервную копию папки cstrike.
2. Скопируйте содержимое папки cstrike/ из архива в папку cstrike/ сервера с заменой.
   Если на сервере уже был AMX Mod X — сохраните свои users.ini и plugins.ini до копирования.
3. Откройте cstrike/liblist.gam и замените строки gamedll:
     Windows:  gamedll "addons\\metamod\\dlls\\metamod.dll"
     Linux:    gamedll_linux "addons/metamod/dlls/metamod.so"
4. VIP и Gold: в addons/amxmodx/configs/users.ini, например
     "STEAM_0:1:12345" "" "t" "ce"     — VIP
     "STEAM_0:1:12345" "" "s" "ce"     — Gold
5. Запустите сервер ОБЯЗАТЕЛЬНО в консольном режиме (-console):
     Windows: положите start_server.bat рядом с hlds.exe и запустите его, или вручную:
              hlds.exe -console -game cstrike +sv_lan 1 +maxplayers 20 +map de_dust2
              (без -console hlds.exe ищет графический модуль AdminServer и падает с ошибкой
               "Assertion failed ... g_hAdminServerModule != NULL")
     Linux:   ./hlds_run -console -game cstrike +maxplayers 20 +map de_dust2
6. В консоли сервера проверьте:
     meta list        — AMX Mod X в статусе RUN
     amxx plugins     — все плагины "running", без "bad load"
   Ошибки смотрите в addons/amxmodx/logs/.

В ИГРЕ
  /menu — главное меню, /guns — оружие, /shop — магазин людей, /vip, /gold, /models
  способность зомби: bind g cso_skill (или G / E / R), рывок человека — двойное W
  админ: amx_deimos_round — следующий раунд заражения будет Раундом Деймоса

Настройки баланса: addons/amxmodx/configs/cso_custom.cfg
Чек-листы проверки: tests/ (в архиве рядом с cstrike/)

Ресурсы CSO в архиве — ваши собственные файлы; архив не для публичного распространения.
"""

if __name__ == "__main__":
    main()
