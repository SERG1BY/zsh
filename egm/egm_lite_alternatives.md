# Alternatives Considered: standalone self-contained Kali-zsh template script for Debian

> **BLUF:** Recommended option **A** — one self-contained `kali-zsh-setup.sh` with the Kali templates (`/etc/skel/.zshrc`, `.zprofile` from kali-defaults, branch `kali/master`) embedded verbatim as heredocs. The script runs directly on the target Debian machine, installs Debian APT packages, deploys configs locally and switches shells via `chsh`. No SSH, no Kali host, no second machine — copy the single file anywhere and run it.

---

## Option A (recommended): single-file script with embedded Kali templates

1. **Embedded templates**: verbatim Kali `/etc/skel/.zshrc` (10.8 KB) and `.zprofile` (336 B) as `cat <<'KALI_ZSHRC'` heredocs inside the script. Verified upstream source: `https://gitlab.com/kalilinux/packages/kali-defaults/-/raw/kali/master/etc/skel/.zshrc`. The template guards every optional plugin source with `[ -f ... ]`, so it degrades gracefully on a minimal system.
2. **Runs locally**: script executes on the target Debian box itself. Auto-elevation: if not root and `sudo` exists, re-exec via `sudo`; otherwise demand root.
3. **Packages**: `apt-get install zsh zsh-syntax-highlighting zsh-autosuggestions command-not-found` from Debian repos. Fatal only if `zsh` itself cannot be installed; optional plugins install best-effort (template tolerates absence).
4. **Same proven mechanics, minus SSH**: timestamped backups (`/etc/zsh-system-backup-<TS>`, `~/.zsh-backup-<TS>`) with restore scripts, `chsh` switch with pre/post validation gates, idempotent re-runs, harvest of existing `.bashrc` customizations into a marker-guarded block.

*Trade-off:* ~10 KB of template text inside the script makes it longer, but the artifact is one file — trivially copyable to any Debian machine (scp, USB, curl), works with zero network after packages are cached.

## Option B: script + `files/` template directory copied alongside

Script sources `.zshrc`/`.zprofile` from a directory next to itself.

*Trade-off:* Still portable, and templates diff cleanly against upstream — but two artifacts to move, and "копироваться в любое место" invites partial-copy failure (script without its `files/`). Worse fit for the stated requirement.

## Option C: script downloads templates at runtime from GitLab

`curl` the kali-defaults raw files on first run.

*Trade-off:* Rejected: breaks autonomy (no network → no templates), adds a supply-chain dependency at run time, and GitLab may be unreachable on the target. Embedding (A) needs network only for APT, which is unavoidable anyway.
