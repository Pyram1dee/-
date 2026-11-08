# Claude Code - CSO Zombie 1.6 Custom Edition

Read `docs/TECH_SPEC_RU.md` and `docs/IMPLEMENTATION_PLAN.md` before making changes.

Goal: implement a reproducible, maintainable Counter-Strike 1.6 Zombie Plague 4.3 FIX modpack. This repository is a specification and starter scaffold, NOT a playable server distribution.

Rules:
1. Never claim a plugin compiles or works unless you actually compile/test it.
2. Preserve original ZP 4.3 FIX API compatibility. Do not use ZA.RU or REZP as the base.
3. Write AMX Mod X Pawn source in `src/`; generated `.amxx` goes to `build/plugins/` and is not committed.
4. Avoid editing core ZP when an independent plugin can do the job.
5. Do not invent or redistribute copyrighted Valve/Nexon/third-party models, sounds or binaries. Keep manifest entries and request legally obtained assets.
6. Add CVARs for gameplay balance, defensive entity cleanup, round-state checks and cooldowns.
7. Validate all key mappings against GoldSrc client commands; never assume G/E/R can be detected reliably without explicit bindings or supported command hooks.
8. Every milestone needs a test checklist and build log.
9. Implement one feature at a time, prioritize working server over flashy features.
10. Communicate in Russian. Record decisions in `docs/DECISIONS.md`.

First task: inspect available server files and AMXX/ZP includes; report missing dependencies; build minimal working plugin and verification workflow before adding gameplay.
