# Goldfish Spec Review — Round 14 (egm_lite_checklist.md rev 14)

Reviewer: adversarial fresh-context spec review. Baseline: rev 14 (commit d2a201b), nothing implemented; no AST/code-diff checks (per round contract).

## Round-13 resolution check: all resolved

Verified in rev 14 text, not relitigated:

1. Per-user backup dir user-owned + mode 0700 + backup-mode fixture — line 24 + line 30. Resolved.
2. `~/.zcompdump` existence-fact in per-user snapshot, restore deletes when recorded absent, restore fixture asserts deletion — line 24 + line 30. Resolved.
3. Staging pinned to target filesystem (per-user: inside home; skel: inside `/etc`), same-device atomic rename, staging-cross-device fixture — line 26 + line 30. Resolved.
4. Four new fixtures present: pipe-run guard, pam_environment, flock-busy, chsh-failure — line 30. Resolved.

## New findings

### 1. [P1] `restore-user.sh` исполняется от root из user-owned каталога — окно локального повышения привилегий

Evidence: line 24 — `restore-user.sh` генерируется внутрь `~/.zsh-backup-<UTC>_<PID>` с владельцем-user и mode 0700; line 18 — ERR/INT/TERM-трапы исполняют уже записанные per-user restore-скрипты; lines 26–27 — rollback при deploy-failure и при user-local gate-failure запускает `restore-user.sh`. Mode 0700 user-owned даёт владельцу право записи в КАТАЛОГ ⇒ user может переименовать/заменить файл внутри, даже если сам файл root-owned. Политика коллизий блокирует только pre-созданный каталог, не подмену внутри работающего запуска.

Цепочка: враждебный локальный user (угрозы этого класса уже в threat-model: hostile-caller-env fixture, foreign-owner skips) заранее кладёт зловредный `~/.zshenv` (preflight-аудит `.zshenv` — только WARN, не skip, line 20), ставит inotify-наблюдение за home; в момент появления бэкап-каталога подменяет `restore-user.sh`; gate падает из-за `.zshenv`; probe на чистом HOME проходит ⇒ атрибуция user-local ⇒ root исполняет подменённый байты как код. Итог: произвольный код от root.

Suggested change: сохранить каталог+снапшот-данные user-owned 0700 (приватность раунда 13 не трогать), но сгенерированные restore-скрипты считать root-only исполняемым контентом: параллельно писать root-owned копию каждого `restore-user.sh` в root-only путь (например, внутрь `/etc/zsh-system-backup-*` 0700) и исполнять её во всех точках (трапы, deploy-failure rollback, gate-атрибуция). User-side копия — только данные. Fixture-tamper: user перезаписывает `restore-user.sh` в своём бэкап-каталоге ⇒ исполнены байты root-копии (или ассерт: пользовательские байты никогда не исполняются).

### 2. [P2] Harvest-allowlist может импортировать ZDOTDIR/FPATH-редирект — тот же класс, что аудит считает фатальным

Evidence: allowlist (line 25) — «export/PATH/alias/umask/...» без исключений; deny/warn — PS1, PROMPT_COMMAND, SHELL, `export -f/-n` — без ZDOTDIR/FPATH/PROMPT. Строка `export ZDOTDIR=...` из `~/.bashrc` попадает в marker block. Sentinel ставится ДО блока (line 26: template → sentinel → harvested block) ⇒ gate и smoke проходят, но каждый ДОЧЕРНИЙ zsh-процесс этой сессии (вложенные шеллы, под shell, tmux-наследники) наследует экспортированный ZDOTDIR и читает `$ZDOTDIR/.zshrc` вместо deployed `~/.zshrc` — deploy инертный на самой ходовой интерактивной поверхности, gate/smoke это не видят. FPATH — то же. Дополнительно: pre-existing `~/.zlogin` с ZDOTDIR не сканируется (line 20 сканирует zshenv/profile/pam_environment; `.zlogin` исполняется в каждом логине позже `.zshrc` и экспортирует ZDOTDIR всем потомкам сессии).

Suggested change: добавить ZDOTDIR, FPATH, PROMPT в deny/warn harvest-классификатора (вхождение ⇒ drop строки + WARN, как PS1); расширить per-user ZDOTDIR-скан на `~/.zlogin`. Косвенные векторы (sourced-файл ставит ZDOTDIR) остаются WARN-only — задокументировать как принятый остаток.

### 3. [P2] Порядок flock ↔ sudo re-exec не зафиксирован; эмпирически fd 9 не переживает sudo

Evidence (проверено в контейнере debian:stable, Debian 13): `parent_fd9=OPEN`, `sudo_child_fd9=CLOSED` — sudo закрывает унаследованные fd ≥ 3 в исполняемой команде. Если лок взят до re-exec (line 18 стоит после line 17 в списке задач, но порядок внутри скрипта не закреплён), финальный root-процесс работает без блокировки: «flock -n 9 (fatal if busy)» молча не защищает конвейер мутаций; взаимное исключение держится лишь случайно на промежуточном процессе sudo — поведение не специфицировано и хрупко.

Suggested change: зафиксировать в спеке: лок строго в финальном root-процессе, после решения о re-exec. Fixture: stub sudo, фиксирующий состояние лока в момент re-exec (порядок-ассерт).

### 4. [P2] TOCTOU между preflight-аудитом и per-user deploy не закрыт

Evidence: line 26 — write-through идёт по свежему realpath, а исключения «unresolvable or foreign-target ones were excluded in preflight» — проверка делегирована preflight, на этапе deploy повторный ассерт не требуется. User может mid-run (окно аудит→backup→harvest→deploy) заменить прошедший аудит dotfile симлинком на чужой root-owned файл. Худший случай: `install -o <user> -g <group>` по realpath затирает, например, `/etc/shadow` (замена содержимого + chown на user).

Suggested change: deploy обязан непосредственно перед staging/move повторно ассертить preflight-предикат по свежим lstat/realpath (существует, regular file, в home, same-owner); несовпадение ⇒ skip+WARN (переиспользовать тот же skip-policy). Расширить fixture (d) вариантом с mid-run подменой.

### 5. [P3] Область действия pipe-run guard для root не определена

Evidence: line 17 формулирует guard без ветки («if $0 is not a readable script file ⇒ fatal»), но обоснование (не запустить интерактивный root shell через sudo) относится только к non-root; fixture (line 30) покрывает только non-root со stub sudo. Поведение `bash < script` / `curl | bash` от root — fatal или выполнение — не определено.

Suggested change: указать явно: guard срабатывает в обеих ветках (единообразная модель входа); добавить root-piped ассерт.

### 6. [P3] Группа-метаданные вне owner-only narrowing (restор группу не чинит)

Evidence (эмпирически, Debian 13): `install -m 0644 root:root` поверх `root:lp` даёт `root:root`. Аналогично `install -o <user> -g <primary>` молча меняет группу цели, владевшей `<user>:<other-group>`; документированный restore восстанавливает байты, но не группу — тот же аргумент, которым обоснован owner-narrowing (line 49), остановленный на одном атрибуте раньше. Skel-кейс (line 23): проверка owner=root не ограничивает группу.

Suggested change: расширить предикаты аудита: per-user — existing regular file / symlink target должен быть `<user>:<primary-group>`; skel — `root:root`; иначе skip+WARN (тот же policy, ещё один предикат). Либо явно задекларировать group-drift как принятый остаток в rationale.

### 7. [P3] Семантика re-run при изменившихся harvest-входах не зафиксирована

Evidence: «never duplicate markers on re-run» (line 25) + дрифт-ассерт «byte-identical deployed dotfiles» (line 29): если `~/.bashrc` изменился между запусками — marker block обновляется (тогда ассерт законно падает и нужен новый эталон) или замораживается (тогда новые строки молча не мигрируют; повторный запуск ради новых строк ничего не даёт)? Обе трактовки удовлетворяют текущему тексту.

Suggested change: зафиксировать одну семантику (например: block обновляется только если harvest-output отличается, дрифт-ассерт сравнивает post-refresh байты; либо block заморожен после первой записи — задокументировать) + fixture на изменившийся `.bashrc` во втором запуске.

### 8. [P3] Контракт «stubbable helpers by PATH name» не полен относительно собственной fixture-сети

Evidence: line 30 перечисляет (sudo, getent, apt-get, apt-cache, flock), но fixtures требуют подмены также chsh (chsh-failure fixture; root pre-switch fixture «injected via stub»), zsh/runuser (timeout-classification fixture «TERM-ignoring stub in the gate»; gate-attribution fixture). Реализация, вызывающая chsh по абсолютному пути (параноидальный safe-path выбор), делает эти fixtures непостроимыми.

Suggested change: расширить PATH-name требование на все бинарники, которые подменяют fixtures: chsh, zsh, runuser; указать, что подмена выполняется через PATH внутри контейнера, а не через абсолютные пути в скрипте.

## Empirical probes run (this machine / debian:stable container)

- `bash < script` ⇒ `$0=bash` — подтверждено (обоснование pipe-run guard корректно).
- sudo fd inheritance: parent `OPEN` → sudo-executed process `CLOSED` — подтверждено (finding 3).
- GNU `install -g` перезаписывает группу существующей цели: `root:lp` → `root:root` — подтверждено (finding 6).
- passwordless sudo на хосте отсутствует — root-пробы выполнены в контейнере debian:stable (Debian 13).

## Verdict

Ноль material findings ⇒ LGTM не выдаётся. 8 findings: 1×[P1], 3×[P2], 4×[P3].
