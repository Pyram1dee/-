"""Применяет config/zclass_models.cfg к zp_zombieclasses.ini сервера.

  python3 scripts/apply_zclass_models.py <cstrike_dir> [<cfg>]

Меняет только строку MODELS существующих секций и только если все модели есть на диске.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_map(cfg):
    out = {}
    for line in cfg.read_text(encoding="utf-8").splitlines():
        line = line.split(";", 1)[0].strip()
        if "=" in line:
            k, v = line.split("=", 1)
            out[k.strip()] = [m.strip() for m in v.split(",") if m.strip()]
    return out


def main():
    cs = Path(sys.argv[1])
    cfg = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "config" / "zclass_models.cfg"
    ini = cs / "addons" / "amxmodx" / "configs" / "zp_zombieclasses.ini"
    if not ini.exists():
        print(f"[zclass_models] нет {ini}, пропуск")
        return 0
    mapping = load_map(cfg)
    # окончания строк сохраняем построчно (в файле ZP они смешанные CRLF/LF)
    raw_lines = ini.read_bytes().decode("latin-1").splitlines(keepends=True)
    lines = [ln.rstrip("\r\n") for ln in raw_lines]
    section, seen, changed = None, set(), 0
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            section = s[1:-1]
            continue
        if section in mapping and s.split("=", 1)[0].strip() == "MODELS":
            seen.add(section)
            models = mapping[section]
            missing = [m for m in models if not (cs / "models" / "player" / m / f"{m}.mdl").is_file()]
            if missing:
                print(f"[zclass_models] {section}: нет моделей {missing} на сервере — оставляю как есть")
                continue
            new = "MODELS = " + " , ".join(models)
            if s != new:
                lines[i] = new
                raw_lines[i] = new + raw_lines[i][len(raw_lines[i].rstrip("\r\n")):]
                changed += 1
                print(f"[zclass_models] {section}: {s} -> {new}")
    for sec in set(mapping) - seen:
        print(f"[zclass_models] секции [{sec}] нет в zp_zombieclasses.ini — запустите карту один раз и повторите deploy")
    if changed:
        ini.write_bytes("".join(raw_lines).encode("latin-1"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
