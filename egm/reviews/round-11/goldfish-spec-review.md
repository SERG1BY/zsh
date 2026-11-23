# Goldfish Spec Review — Round 11 (egm_lite_checklist.md, rev 11)

Baseline: rev 11 прочитан полностью (55 строк, включая длинные задачи 20/27/30). AST и диффы `kali-zsh-setup.sh` не проверялись (round 11 — spec-only). Эмпирические пробы на этой машине: Debian 13 (trixie), coreutils 9.7, zsh не установлен; пакеты `zsh`, `zsh-common`, `zsh-syntax-highlighting`, `zsh-autosuggestions`, `command-not-found` скачаны из trixie/main и распакованы (`dpkg-deb -e/-c`).

## Проверка пяти фиксов раунда 10 — все подтверждены (резолюция: да)

1. dpkg caveat переписан (стр. 21): «dpkg не воссоздаёт удалённые conffiles», remedy = `apt-get install --reinstall zsh`; fresh-install сценарий описан явно; `restore-system.sh` печатает команду при удалении recorded-absent `/etc/zsh/*`; fixture есть (стр. 30). Да.
2. Regular-file ownership audit добавлен (стр. 20) + fixture «root:root regular `~/.zshrc`» (стр. 30). Да.
3. Smoke обёрнут в тот же timeout 30s/10s kill-after; класс VALIDATION_TIMEOUT; non-fatal WARN (стр. 29). Да.
4. `mkdir -p /run/lock` до flock (стр. 18). Да.
5. Preflight fatal-класс «unusable environment» перечислен: `getent`/`flock`/`apt-cache`, ноль обнаруженных пользователей (стр. 20) + env-fatal fixtures (стр. 30). Да.

## Пробы, подтвердившие контракт (не находки)

- Пути плагинов из стр. 22 точны для trixie: `/usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh`, `/usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh` (проверено `dpkg-deb -c`).
- `command-not-found` 23.04.0-2 ships `/etc/zsh_command_not_found` + apt-хук `/etc/apt/apt.conf.d/50command-not-found` (ACK-1: база наполняется при apt-операциях).
- `/etc/skel` этой машины: `.bashrc`, `.profile`, `.bash_logout`, `.face` — `.zshrc`/`.zprofile` отсутствуют; `zsh-common` 5.9-8 ships **ноль** файлов в `/etc/skel` (только `/etc/zsh/*`, шесть conffiles).
- zsh/zsh-common maintainer scripts **не трогают** `/etc/shells` (нет `add-shell`). Проверено как кандидат-находка, отклонено: единственный писатель zsh-строк в `/etc/shells` — сам скрипт, значит restore «pre-run bytes» для `/etc/shells` консистентен.
- `runuser`, `flock`, `getent`, `apt-cache`, `chsh`, `/usr/sbin/add-shell`, `/etc/pam.d/runuser` — на месте; `/usr/share/base-files/dot.bashrc` существует (ACK-3 подтверждён).
- `zsh-common` ships шесть conffiles (`zlogin`, `zlogout`, `newuser.zshrc.recommended` сверх трёх снапшотных). Скрипт их не трогает → не снапшотятся; печатаемый reinstall-ремеди чинит всё. Не находка.

## Находки

### 1. [P1] Skel-deploy precondition противоречит главному сценарию — свежий Debian без zsh

Evidence: стр. 23: «skel deploy precondition: a resolved skel target must be an existing regular file owned by root, otherwise skip with WARN». Пробы: на чистом Debian `/etc/skel/.zshrc`/`.zprofile` отсутствуют (локально подтверждено; `zsh-common` ships только `/etc/zsh/*`, ноль skel-файлов) — это ровно «primary target: Debian without zsh» из стр. 21, где backup уже обязана «record absence» skel-путей. Строгая чтение precondition: путь отсутствует ⇒ не «existing regular file» ⇒ skip+WARN. Итог на главной цели: skel-deploy всегда пропускается, новые пользователи не получают Kali zsh, exit 0. Тесты это не ловят: double-run fixture «byte-identical skel copies» проходит вакуумно (отсутствие == отсутствие); fresh-install fixture ассертит только удаление `/etc/zsh/*`; system-symlink fixture предполагает существующий путь.

Change: переформулировать precondition по кейсам — (a) путь отсутствует ⇒ писать; (b) regular file ⇒ owner root, иначе skip; (c) symlink ⇒ resolved target существует, regular, root-owned, иначе skip. В fresh-install fixture добавить ассерт: после запуска `/etc/skel/.zshrc` и `/etc/skel/.zprofile` существуют и их sha256 равны пинам.

### 2. [P2] Системный fatal-скан ZDOTDIR не покрывает `/etc/profile` и `/etc/profile.d/*.sh` — цепочку, которую скрипт сам активирует

Evidence: стр. 20 сканирует только `/etc/zsh/zshenv`, `/etc/zsh/zprofile`, `/etc/zsh/zshrc`, `/etc/environment`, `/etc/security/pam_env.conf`. Стр. 23 добавляет `emulate sh -c '. /etc/profile'` в `/etc/zsh/zprofile`; `emulate sh -c` сорсит в текущем шелле ⇒ exports персистентны (тот же механизм, на котором держится контракт «`.zprofile` → `.profile` chain работает» из стр. 25). `export ZDOTDIR=...` в `/etc/profile.d/*.sh` после этого редиректит `$ZDOTDIR/.zprofile` и `.zshrc` для каждого zsh-логина — deploy инертен машинно: ровно класс, ради которого создан preflight fatal-скан. Сейчас ловится только на gate: probe fails ⇒ systemic abort ⇒ rollback. Исход безопасный, но мутации уже случились и откатились — цель «fatal before any mutation» для этого класса не выполнена.

Change: добавить `/etc/profile` и `/etc/profile.d/*.sh` в системный fatal-скан до мутаций. Опционально: per-user WARN на `export ZDOTDIR` в `~/.profile` (сейчас ловится гейтом с корректной user-local атрибуцией — WARN лишь ранняя диагностика).

### 3. [P3] Коллизия timestamped backup-каталогов при быстрых повторных запусках не специфицирована

Evidence: стр. 21/24 — каталоги `/etc/zsh-system-backup-<UTC>` и `~/.zsh-backup-<UTC>`; стр. 29 — backup-артефакты «legitimately change on every run» ⇒ каждый запуск создаёт новые каталоги. Гранулярность `<UTC>` не задана; два запуска в пределах одной секунды (скриптовый double-run) сталкиваются на одном имени; поведение при существующем каталоге (fatal? merge? запись поверх «immutable baseline»?) не определено. Double-run fixture вряд ли поймает (между запусками >1 с).

Change: задать гранулярность (секунды + наносекунды/PID) и явную политику при существующем каталоге (fatal или новый суффикс); ассерт «baseline dir пуст до записи».

## Итог

3 находки: 1×P1, 1×P2, 1×P3. LGTM не выдаётся.
