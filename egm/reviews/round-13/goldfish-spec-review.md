# Goldfish Spec Review — Round 13 (egm_lite_checklist.md, rev 13)

Baseline: rev 13 прочитан полностью (55 строк; длинные задачи 20/27/30 извлечены целиком, без усечения). AST и диффы `kali-zsh-setup.sh` не проверялись (round 13 — spec-only, имплементации ещё нет). Пробы на этой машине: coreutils 9.7, zsh не установлен; `umask 0002` ⇒ `mkdir` даёт 0755/0775; `env -u KALI_ZSH_SETUP_ACTIVE` в цепочке `env … sh -c 'env'` — переменная не видна потомку (grep -c = 0).

## Проверка четырёх фиксов раунда 12 — все подтверждены (резолюция: да)

1. Gate и smoke стрипают `-u KALI_ZSH_SETUP_ACTIVE` (плюс `-u PROMPT -u PS1`, `-u ZDOTDIR -u FPATH`): стр. 27 и стр. 29; объяснение (re-run изнутри post-switch zsh-логина) записано в gate-задаче. Да.
2. Hostile-caller-env fixture (экспортированный sentinel + нерабочий rc ⇒ gate FAILS, нет false validation) и ZDOTDIR-class fixtures (`/etc/profile.d/x.sh` ⇒ preflight и main exit non-zero, ноль мутаций; `~/.zshenv`/`~/.profile` ⇒ per-user skip+WARN, остальные идут): стр. 30. Да. Пробел по `~/.pam_environment` — находка 2.
3. `~/.pam_environment` добавлен в per-user ZDOTDIR-audit (стр. 20) с корректной рациональю (`user_readenv` off/deprecated, admin opt-in невидим гейту). Да. Пробел по fixture — находка 2.
4. Re-exec guard: `$0` не читаемый script-файл ⇒ fatal с объяснением (стр. 17). Да. Пробел по fixture — находка 1.

## Находки

### 1. [P2] Re-exec guard (round-12 фикс) не покрыт fixture — единственный fatal-класс без теста

Evidence: стр. 30 покрывает обе ветки привилегий — «re-exec via `sudo` when non-root (emulated, e.g. stub `sudo` in PATH) and fatal-with-message when `sudo` absent» — но ветка «`$0` не читаемый script-файл ⇒ fatal» (стр. 17, сам round-12 fix) в списке fixture-тестов отсутствует. Стандарт чеклиста — fixture на каждый fatal-класс (env-fatal fixtures, --preflight exit assert, hash mismatch…). Guard защищает от запуска интерактивного root-шелла при `curl … | bash` — поведение safety-критичное и новое; регрессия здесь невидима существующим тестам.

Change: добавить fixture — не-root запуск с `$0`, не являющимся script-файлом (эмуляция: `bash < kali-zsh-setup.sh` ⇒ `$0="bash"`, либо `bash -c 'exec -a /nonexistent …'`), stub `sudo` в PATH присутствует ⇒ ассерт: non-zero exit, объясняющее сообщение, `sudo` не вызван, root-ветка не затронута.

### 2. [P2] `~/.pam_environment` добавлен в audit (стр. 20), но отсутствует в ZDOTDIR-class fixtures — путь без страховки гейтом

Evidence: fixture перечисляет только `/etc/profile.d/x.sh` (fatal) и `~/.zshenv`, `~/.profile` (per-user skip): стр. 30. Для `~/.pam_environment` гейт-страховки нет по construction: и gate, и probe, и smoke идут через `runuser`, а `/etc/pam.d/runuser` не содержит pam_env (verified) — sentinel-assert и probe НЕ поймают admin-opt-in `user_readenv`: реальный логин получит ZDOTDIR, deploy будет инертен, все проверки пройдут. Audit — единственная линия защиты именно для этого источника, и она не тестируется (механизм свежий, round-12; опечатка в имени файла ⇒ audit молча не срабатывает).

Change: расширить ZDOTDIR-class fixture — `ZDOTDIR=…` в `~/.pam_environment` ⇒ ассерт per-user skip+WARN, пользователь не переключён, остальные идут.

### 3. [P2] Режим per-user backup-каталога не специфицирован — world-readable копия `.profile` при дефолтном umask

Evidence: системный backup задан как «0700 root» (стр. 21), probe HOME — «owner=<user> and mode 0700» (стр. 27); per-user backup — только «with user ownership (same collision policy…)» (стр. 24), режим не указан. Проба: umask 0002 ⇒ `mkdir` даёт 0755/0775 — world-readable. В каталог попадают `.profile`, `.bashrc`, `.bash_aliases`, `restore-user.sh`: у пользователя с home 0700 или dotfile 0600 (exports с секретами) backup даёт privacy-даунгрейд для всех локальных пользователей. Асимметрия с явно заданным 0700 системного каталога — упущение, не решение.

Change: закрепить в стр. 24 «0700, владелец <user>» (зеркало системного контракта) и добавить в fixture-набор ассерт режима `~/.zsh-backup-*` = 0700.

### 4. [P3] Fatal «flock busy» не покрыт fixture

Evidence: стр. 18 — `flock -n 9` fatal if busy; env-fatal fixtures (стр. 30) покрывают только отсутствие бинарника `flock`, не конкуренцию за лок. Поведение «второй экземпляр ⇒ немедленный non-zero exit, ноль мутаций» не ассертится.

Change: fixture — сторонний процесс держит `/run/lock/kali-zsh-setup.lock`, запуск скрипта ⇒ немедленный non-zero exit, ни backup-каталога, ни других мутаций.

### 5. [P3] Контракт `restore-user.sh` на `~/.zcompdump` требует записи факта существования, которого нет в snapshot-списке стр. 24

Evidence: стр. 27 — «`restore-user.sh` deletes it when it did not exist pre-run»; snapshot-список стр. 24 содержит `.bashrc`, `.bash_aliases`, `.profile`, `.zshrc`/`.zprofile`/`.zshenv` — `~/.zcompdump` не упомянут. Реализация по стр. 24 в одиночку либо не удалит run-артефакт, либо (хуже) удалит pre-existing файл пользователя. Внутренняя несогласованность двух задач.

Change: добавить в стр. 24 запись факта существования `~/.zcompdump` (existence fact, не копирование байт) в per-user backup.

### 6. [P3] «Atomic» deploy не привязан к файловой системе цели — cross-device `mv` не атомарен

Evidence: стр. 26 — «stage both files first, then move both into place» (атомарность — заявленное свойство); место staging-каталога не задано (стр. 18 — только «EXIT removes staging dir»). `mv` между ФС — copy+unlink: краш в окне копирования оставляет усечённый целевой файл — ровно отказ, от которого заявлена атомарность. Касается и skel-deploy.

Change: закрепить staging внутри каталога-цели (home пользователя / `/etc/skel`) либо явно записать ограничение «staging на той же ФС, что цель».

### 7. [P3] Ветка «failed non-root `chsh` ⇒ WARN and continue» без fixture

Evidence: стр. 28 определяет ветку (WARN, остальные пользователи идут, dotfiles остаются задеплоенными, rollback-команда уже внутри `restore-user.sh`); skip-policy fixtures (a)–(e) покрывают backup-failure и pre-switch причины, но не отказ `chsh`.

Change: fixture — stub `chsh`, падающий для одного пользователя ⇒ ассерт: WARN, его shell не изменён, задеплоенные dotfiles сохранены, остальные переключены, exit 0.

## Итог

Round-12 фиксы подтверждены. Новые находки — пробелы test-плана (1, 2, 4, 7) и два недоспецифицированных контракта (3, 5, 6); контрадикций принятым политикам нет.
