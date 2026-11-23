# Goldfish Spec Review — round 8

Target: `egm/egm_lite_checklist.md` (rev 8). Scope: spec review only, no AST/code-diff checks (nothing implemented).
Baseline probes run on this Debian 13 host (coreutils 9.7, zsh absent): pinned templates fetched and sha256-verified (`56ad0fc1…`, 10882 B; `54ccdd24…`, 336 B); template body grep — no early `return`/`exit` lines; template lines 50–52 set `HISTFILE=~/.zsh_history`, `SAVEHIST=2000`; `/etc/pam.d/runuser` contains **no `pam_env`** (while `/etc/pam.d/su` does); `runuser(1)` manpage: without `-l` only HOME/SHELL(/USER/LOGNAME) are set, the rest of the caller's environment is preserved, final env modification via PAM.

## Round-7 resolution check (7 items)

1. Probe HOME owner/mode — resolved (line 27: owner=<user>, mode 0700).
2. Sentinel in gate+smoke — present in both; but its interplay with the probe seed is self-contradictory → Finding 1.
3. Mixed fixture (3 users) — present (line 30); realizable only after Finding 1 is fixed.
4. apt fetch-fallback severity split — resolved (line 22) + fixture present.
5. Exit contracts (preflight + main run) — present and mutually consistent (lines 20, 29).
6. Skel symlink discipline + preview WARN — mostly resolved (lines 20, 23); residual restore/precondition gaps → Finding 5.
7. Same-owner symlink narrowing — present in normative lines (line 20); stale rationale contradicts it → Finding 8.

## Findings

### 1. [P0] Probe seed lacks the sentinel that the (identical) probe gate asserts — attribution discriminator cannot pass, contradicting its own fixtures

Evidence: line 27 — "re-run the **identical gate** … pre-seeded with **only the embedded template** (no harvested marker block, no user dotfiles)" and "(the probe HOME **has no sentinel** either)". Line 26 defines the deployed file as "embedded template **+ a managed sentinel line** + harvested marker block", i.e. the sentinel is NOT part of the embedded template. The gate command ends with `… && [[ -n $KALI_ZSH_SETUP_ACTIVE ]] && exit 0`. Consequence: the probe seed has no sentinel, the identical gate asserts the sentinel, therefore the probe **fails by construction for every user** → every gate failure classifies as systemic → global abort (or, under the mixed-set rule, everything becomes "probe-failing" ⇒ skip+WARN). Line 30 requires the opposite: gate-attribution fixture expects "the clean-temp-HOME differential probe **passes** for each (user-local branch asserted)" and the mixed fixture expects a real distinction between broken-dotfiles and probe-failing users. The spec asserts mutually exclusive behaviors.

Fix (one sentence + one correction): define the probe seed as "embedded template **plus the managed sentinel line**" (i.e., the deployed `.zshrc` minus the marker block), and replace "(the probe HOME has no sentinel either)" with the accurate statement: under a ZDOTDIR source the probe fails because its rc files are not read — the sentinel assert fails in both runs, preserving the round-7 systemic-abort goal for ZDOTDIR hijacks.

### 2. [P2] Gate/smoke inherit the invoking root environment; a caller's ZDOTDIR/FPATH causes a false systemic abort on a healthy machine

Evidence: line 27/29 commands are `runuser -u <user> -- env HOME=<home> TERM=xterm-256color … zsh`. `runuser(1)` (verified manpage, Debian 13): without `-l` it sets only HOME/SHELL(/USER/LOGNAME) and preserves all other environment. An operator running the script from a zsh configured with `ZDOTDIR=~/.config/zsh` (common with grml/oh-my-zsh-style setups) propagates ZDOTDIR into every gate, probe and smoke invocation ⇒ rc files are read from the wrong directory ⇒ sentinel assert fails everywhere ⇒ probe fails ⇒ false systemic abort, no chsh, run exits non-zero on a perfectly healthy machine. Same risk for FPATH.

Fix: sanitize in gate, probe and smoke: `env -u ZDOTDIR -u FPATH HOME=<home> TERM=xterm-256color …` (state it explicitly in lines 27/29; one clause each).

### 3. [P2] PAM-imported ZDOTDIR (/etc/environment, /etc/security/pam_env.conf) is invisible to gate+probe+smoke yet makes deployed dotfiles inert in real logins

Evidence: preflight audits ZDOTDIR only in `/etc/zsh/zshenv` (system) and `~/.zshenv` (per user). Real logins (login, sshd, display managers) import `/etc/environment` and `/etc/security/pam_env.conf` via `pam_env readenv=1`; verified on this Debian 13 host: `/etc/pam.d/runuser` contains no `pam_env`, so the gate never sees such a ZDOTDIR ⇒ sentinel assert passes ⇒ users get chsh'd ⇒ real login sessions then read `$ZDOTDIR/.zshrc` and the deployed files are inert — exactly the failure class round-7 fix 2 claims to eliminate ("an undetected ZDOTDIR source makes gate+probe fail everywhere"; that claim only holds for env sources visible to the gate).

Fix: extend the preflight system-level ZDOTDIR scan (fatal-class, same as `/etc/zsh/zshenv`) to `/etc/environment` and `/etc/security/pam_env.conf`; one clause in line 20.

### 4. [P2] [UNVERIFIED] Gate/smoke run with the template's SAVEHIST=2000/HISTFILE=~/.zsh_history; likely writes user-home history, and the drift contract neither excludes it nor scopes "dotfiles"

Evidence: template lines 50–52 (`HISTFILE=~/.zsh_history`, `SAVEHIST=2000`); the gate/smoke shells are `-l -i` (interactive) and the gate payload ends with `exit 0`, i.e. an interactive exit path that typically saves history. If `zsh -i -c` saves history (not testable here — zsh absent on this host), every gate/smoke writes into each user's real `~/.zsh_history`: an unrequested home mutation, and on the second run the bytes differ ⇒ the "double-run: zero diffs across every asserted path" assertion can false-fail, because the drift exclusion list (apt lists, `~/.zcompdump`, backup artifacts) does not cover `~/.zsh_history` and "byte-identical dotfiles" is not explicitly scoped to the deployed files.

Fix (cheap and safe under either behavior): prepend history suppression to both `-c` payloads (e.g. `SAVEHIST=0 HISTFILE=/dev/null; …`) and scope the drift assertion explicitly to the deployed files (`.zshrc`, `.zprofile`, marker block byte-identity) instead of "dotfiles" generally.

### 5. [P2] Link-preserving restore semantics and deploy preconditions are defined only for per-user paths; system-snapshot paths (incl. skel) fall through

Evidence: line 24 defines symlink snapshot semantics ("stores separately the fact that it was a link and the bytes of its target; restore writes target bytes through the existing link") — scoped to per-user backup. Line 21 (system backup: `/etc/zsh/zprofile`, `/etc/zsh/zshenv`, `/etc/zsh/zshrc`, `/etc/shells`, `/etc/skel/.zshrc`, `/etc/skel/.zprofile`, …) says nothing about links ⇒ `restore-system.sh` would replace an admin's symlink with a regular file. Line 23 (skel deploy) reuses the per-user "symlink discipline" (realpath write, `[ -L ]` assert) but omits the per-user preflight preconditions: no "resolved target must be an existing regular file" check (a directory target would make `install` write `dir/basename`) and no foreign-owned-target policy (write-through would chown a shared/package target to root). Line 20 only WARNs on symlinked skel dotfiles, then deploy proceeds regardless.

Fix: (a) extend line 21/24 semantics — every snapshotted path, system and per-user, gets the same link-preserving snapshot/restore contract; (b) line 23: skel deploy requires the resolved target to be a regular file, else skip that skel file with WARN + report; (c) add a symlinked skel path to the restore-system round-trip fixture.

### 6. [P2] Test suite has no isolation substrate: fixtures mutate /etc, /etc/skel, create users and homes — "concrete and runnable" is not met

Evidence: line 30 fixtures require real multi-user setups (three-user mixed fixture, users created, homes populated), host-level mutations (`/etc/zsh/*`, `/etc/skel`, `/etc/shells`, `chsh`, `/etc/default/useradd`, `/etc/adduser.conf`), and PATH stubs (`sudo`, `getent`, `apt-get`). No mechanism is named for isolating these from the machine running the tests (container/chroot/mount-namespace), and PATH stubs only work if the script invokes those helpers by PATH-resolvable names (unstated). As written, the suite is either destructive on the dev host or not implementable without inventing a harness.

Fix: state the substrate explicitly (e.g., privileged throwaway container per fixture, or a chroot with bind-mounted fixtures), and require PATH-name invocation of stubbed helpers in the script contract.

### 7. [P3] sudo re-exec uses bare `"$0"` — secure_path can execute a different file with root privileges

Evidence: line 17: `sudo -- "$0" "$@"`. If the script is invoked by bare name via the user's PATH (e.g. `~/bin/kali-zsh-setup.sh`), sudo resolves the name through `secure_path`; a stale copy in `/usr/local/bin` would be executed as root instead of the intended file (or sudo fails "command not found"). Fix: resolve first: `sudo -- "$(readlink -f -- "$0")" "$@"`.

### 8. [P3] Stale rationale contradicts the round-7 ownership narrowing

Evidence: line 49 — "Symlink write-through restricted to targets **owned by the user or located inside their home**" vs line 20 (round-7 fix 7) — same-owner only; a foreign-owned target inside the home is skipped. An implementer following the rationale would reopen the chown-damage hole the fix closed. Fix: reword line 49 to "targets owned by the user (round-7 narrowing: foreign-owned targets inside the home are skipped)".

### 9. [P3] Root pre-switch login check: purpose and failure consequence unmapped

Evidence: line 28 — "root last with pre-switch login check" defines neither what the check tests nor what happens on failure (skip root with WARN? fatal?). Every other failure in the run has a mapped outcome; this one does not. Fix: define it, e.g. active-session detection is informational; check failure ⇒ skip root switch with WARN + report (consistent with the skip-and-continue policy), or explicitly mark it fatal if the root switch is mandatory.

### 10. [P3] Smoke command cannot yield its own pass criterion (sentinel not printed)

Evidence: line 29 — exact smoke command is `zsh -l -i -c 'print -r -- $PROMPT'`, but the pass criterion additionally requires "non-empty `$KALI_ZSH_SETUP_ACTIVE`" — a value the command never emits, so the criterion is unobservable as written. Fix: extend the payload, e.g. `print -r -- $PROMPT; [[ -n $KALI_ZSH_SETUP_ACTIVE ]] && print -r -- SENTINEL_OK`.

## Probes performed (this host)

- Pinned templates re-fetched from `gitlab.com/kalilinux/packages/kali-defaults` raw `kali/master`; sha256 and byte sizes match the pinned contract.
- Template body: no early `return`/`exit` ⇒ appended sentinel always executes in interactive shells (round-7 fix 2 sound on this axis).
- Template lines 50–52: `HISTFILE`/`SAVEHIST` confirmed (Finding 4).
- `/etc/pam.d/runuser` vs `/etc/pam.d/su`: pam_env absent/present respectively (Findings 2, 3).
- `runuser(1)` manpage: non-login env preservation + PAM final modification (Findings 2, 3).
- sudo requires a password on this host ⇒ no live root probes needed or performed.
