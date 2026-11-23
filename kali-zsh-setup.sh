#!/usr/bin/env bash
# kali-zsh-setup.sh — System-wide Kali-identical zsh deployment on Debian across all profiles
# Conforms to EGM-Lite specification rev 16

set -euo pipefail

# Defaults
SOURCE_ALIAS="kali"
TARGET_ALIAS="debian"
PREFLIGHT_ONLY=0
FORCE_UNLOCK=0
USE_KALI_PATH=0

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15)
SCP_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15)

usage() {
    cat <<EOF
Usage: $0 [options]
Options:
  --source=ALIAS    SSH alias for Kali source host (default: kali)
  --target=ALIAS    SSH alias for Debian target host (default: debian)
  --kali-path       Prepend live Kali login PATH baseline to user configurations
  --preflight       Run read-only preflight checks and discovery, then exit 0
  --force-unlock    Override and remove any existing concurrency lock on target
  --help            Show this help message
EOF
    exit 0
}

for arg in "$@"; do
    case "$arg" in
        --source=*) SOURCE_ALIAS="${arg#*=}" ;;
        --target=*) TARGET_ALIAS="${arg#*=}" ;;
        --kali-path) USE_KALI_PATH=1 ;;
        --preflight) PREFLIGHT_ONLY=1 ;;
        --force-unlock) FORCE_UNLOCK=1 ;;
        --help) usage ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

# Remote command helpers with robust shell escaping
remote_exec() {
    local escaped_cmd=""
    if [ "$#" -gt 0 ]; then
        escaped_cmd=$(printf '%q ' "$@")
    fi
    ssh "${SSH_OPTS[@]}" "$TARGET_ALIAS" "$escaped_cmd"
}

remote_sudo() {
    local escaped_cmd=""
    if [ "$#" -gt 0 ]; then
        escaped_cmd=$(printf '%q ' "$@")
    fi
    ssh "${SSH_OPTS[@]}" "$TARGET_ALIAS" "sudo -n $escaped_cmd"
}

# Cleanup and abort traps
LOCAL_STAGING=""
REMOTE_STAGING=""

cleanup_local() {
    if [ -n "$LOCAL_STAGING" ] && [ -d "$LOCAL_STAGING" ]; then
        rm -rf "$LOCAL_STAGING"
    fi
}

cleanup_remote() {
    if [ -n "$REMOTE_STAGING" ]; then
        remote_sudo rm -rf "$REMOTE_STAGING" 2>/dev/null || true
    fi
    remote_sudo rm -f /var/run/kali-zsh-setup.lock 2>/dev/null || true
}

handle_abort() {
    local exit_code="$?"
    echo "[-] Aborting execution (exit code: $exit_code). Triggering rollback..." >&2
    
    # Run discovered user rollbacks if present
    if [ -n "${DISCOVERED_USERS:-}" ]; then
        for u in $DISCOVERED_USERS; do
            local u_home=""
            u_home=$(remote_exec getent passwd "$u" | cut -d: -f6)
            if [ -n "$u_home" ] && remote_exec [ -x "$u_home/.zsh-backup-latest/restore-user.sh" ]; then
                echo "[*] Restoring user $u..."
                remote_sudo "$u_home/.zsh-backup-latest/restore-user.sh" || true
            fi
        done
    fi

    # Run system rollback if present
    if remote_exec [ -x /etc/zsh-system-backup-latest/restore-system.sh ]; then
        echo "[*] Restoring system /etc/ configuration..."
        remote_sudo /etc/zsh-system-backup-latest/restore-system.sh || true
    fi

    cleanup_remote
    cleanup_local
    exit "$exit_code"
}

trap 'handle_abort $?' ERR INT TERM
trap 'cleanup_local; cleanup_remote' EXIT

echo "[*] Initializing local staging directory..."
LOCAL_STAGING=$(mktemp -d /tmp/kali-zsh-local-XXXXXX)

echo "[*] Verifying SSH connectivity and passwordless sudo..."
remote_sudo true || { echo "[!] Passwordless sudo required on $TARGET_ALIAS" >&2; exit 1; }
ssh "${SSH_OPTS[@]}" "$SOURCE_ALIAS" true || { echo "[!] Cannot reach source host $SOURCE_ALIAS" >&2; exit 1; }

echo "[*] Fetching pristine templates from $SOURCE_ALIAS:/etc/skel/..."
scp "${SCP_OPTS[@]}" "$SOURCE_ALIAS:/etc/skel/.zshrc" "$LOCAL_STAGING/.zshrc"
scp "${SCP_OPTS[@]}" "$SOURCE_ALIAS:/etc/skel/.zprofile" "$LOCAL_STAGING/.zprofile"

# Verify signature anchors
grep -q "PROMPT_ALTERNATIVE" "$LOCAL_STAGING/.zshrc" || { echo "[!] Invalid .zshrc template missing signature anchor" >&2; exit 1; }
grep -q ".profile" "$LOCAL_STAGING/.zprofile" || { echo "[!] Invalid .zprofile template missing .profile source" >&2; exit 1; }

echo "[*] Discovering interactive accounts on $TARGET_ALIAS..."
DISCOVERED_USERS_RAW=$(remote_exec getent passwd | awk -F: '$3 == 0 || $3 >= 1000 {print $1 ":" $6 ":" $7}')
DISCOVERED_USERS=""
for entry in $DISCOVERED_USERS_RAW; do
    shell=$(echo "$entry" | cut -d: -f3)
    case "$shell" in
        */nologin|*/false|*/sync) continue ;;
    es:*) ;;
    *)
        user=$(echo "$entry" | cut -d: -f1)
        DISCOVERED_USERS="${DISCOVERED_USERS:+$DISCOVERED_USERS }$user"
        ;;
    esac
done

echo "[+] Discovered interactive users: $DISCOVERED_USERS"

echo "[*] Performing external contract and prerequisite verification..."
remote_sudo grep -q '^SHELL=' /etc/default/useradd || { echo "[!] Missing SHELL= in /etc/default/useradd" >&2; exit 1; }
remote_sudo grep -qE '^[#]?[[:space:]]*DSHELL=' /etc/adduser.conf || { echo "[!] Missing DSHELL= in /etc/adduser.conf" >&2; exit 1; }

remote_exec apt-cache policy zsh zsh-syntax-highlighting zsh-autosuggestions command-not-found >/dev/null || {
    echo "[!] Required APT packages missing from repository cache on $TARGET_ALIAS" >&2
    exit 1
}

# Pre-existing dotfiles and profile safety audit
for u in $DISCOVERED_USERS; do
    u_home=$(remote_exec getent passwd "$u" | cut -d: -f6)
    echo "[*] Auditing profile for user: $u (home: $u_home)"
    
    # Check .profile for unportable bash constructs
    if remote_exec [ -r "$u_home/.profile" ]; then
        if remote_exec grep -qE '(shopt|complete|\bdeclare\s+-A|\btypeset\s+-A)' "$u_home/.profile"; then
            echo "[!] WARN: User $u has unportable bash constructs in .profile that may fail under zsh emulate sh" >&2
        fi
    fi

    # Dotfile symlink audit
    for dot in .zshrc .zprofile; do
        if remote_exec [ -L "$u_home/$dot" ]; then
            echo "[!] WARN: User $u has symlinked $dot. Write-through to realpath will be used." >&2
        fi
    done
done

# Capture Kali login PATH baseline if requested
KALI_LOGIN_PATH=""
if [ "$USE_KALI_PATH" -eq 1 ]; then
    echo "[*] Capturing live Kali login PATH baseline..."
    KALI_LOGIN_PATH=$(ssh "${SSH_OPTS[@]}" "$SOURCE_ALIAS" "zsh -l -c 'print -r -- \$PATH'")
fi

if [ "$PREFLIGHT_ONLY" -eq 1 ]; then
    echo "[+] Preflight checks completed successfully. --preflight specified, exiting 0."
    exit 0
fi

echo "[*] Entering mutation phase: checking concurrency lock..."
lock_exists=$(remote_exec [ -f /var/run/kali-zsh-setup.lock ] && echo 1 || echo 0)
if [ "$lock_exists" -eq 1 ]; then
    if [ "$FORCE_UNLOCK" -eq 1 ]; then
        echo "[!] --force-unlock specified: removing stale lock."
        remote_sudo rm -f /var/run/kali-zsh-setup.lock
    else
        lock_age_min=$(remote_sudo python3 -c 'import os, time; print(int((time.time() - os.path.getmtime("/var/run/kali-zsh-setup.lock")) / 60))' 2>/dev/null || echo 0)
        if [ "$lock_age_min" -ge 30 ]; then
            echo "[!] WARN: Concurrency lock is stale ($lock_age_min minutes old). Use --force-unlock to override." >&2
            exit 1
        else
            echo "[!] Error: Concurrency lock exists on target ($TARGET_ALIAS). Another run is active." >&2
            exit 1
        fi
    fi
fi

echo "[*] Acquiring concurrency lock..."
remote_sudo sh -c "echo 'PID: $$ TIME: $(date -u +%FT%TZ)' > /var/run/kali-zsh-setup.lock"

echo "[*] Setting up remote staging directory..."
REMOTE_STAGING=$(remote_exec mktemp -d /tmp/zsh-staging-XXXXXX)
remote_exec chmod 700 "$REMOTE_STAGING"
remote_exec mkdir -p "$REMOTE_STAGING/skel"
for u in $DISCOVERED_USERS; do
    remote_exec mkdir -p "$REMOTE_STAGING/users/$u"
done

echo "[*] Creating system-wide backup stage..."
TS=$(date -u +%Y%m%dT%H%M%SZ)
SYS_BACKUP="/etc/zsh-system-backup-$TS"
remote_sudo mkdir -p "$SYS_BACKUP"
remote_sudo chmod 700 "$SYS_BACKUP"

if ! remote_sudo [ -e /etc/zsh-system-backup-baseline ]; then
    remote_sudo cp -a /etc/zsh "$SYS_BACKUP/zsh-baseline" 2>/dev/null || true
    remote_sudo ln -s "$SYS_BACKUP" /etc/zsh-system-backup-baseline
fi
remote_sudo rm -f /etc/zsh-system-backup-latest
remote_sudo ln -s "$SYS_BACKUP" /etc/zsh-system-backup-latest

# Snapshot system files
for f in /etc/zsh/zprofile /etc/zsh/zshenv /etc/zsh/zshrc /etc/shells /etc/skel/.zshrc /etc/skel/.zprofile /etc/default/useradd /etc/adduser.conf; do
    if remote_exec [ -f "$f" ]; then
        remote_sudo cp -p "$f" "$SYS_BACKUP/"
    fi
done

# Generate system rollback script
remote_sudo tee "$SYS_BACKUP/restore-system.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR="$(dirname "$0")"
echo "[*] Restoring system configuration from $BACKUP_DIR..."
for f in zprofile zshenv zshrc shells .zshrc .zprofile useradd adduser.conf; do
    if [ -f "$BACKUP_DIR/$f" ]; then
        cp -p "$BACKUP_DIR/$f" /etc/$( [ "$f" = "useradd" ] && echo "default/useradd" || [ "$f" = "adduser.conf" ] && echo "adduser.conf" || [ "$f" = ".zshrc" -o "$f" = ".zprofile" ] && echo "skel/$f" || echo "zsh/$f" )
    fi
done
echo "[+] System restore completed. (Note: APT packages were preserved intentionally)."
EOF
remote_sudo chmod +x "$SYS_BACKUP/restore-system.sh"

echo "[*] Installing Debian APT packages for zsh and plugins..."
remote_sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq -o DPkg::Lock::Timeout=60
remote_sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -o DPkg::Lock::Timeout=60 -o DPkg::Options::=--force-confold \
    zsh zsh-syntax-highlighting zsh-autosuggestions command-not-found

# Assert post-install file existence
remote_exec [ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]
remote_exec [ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]
remote_exec [ -f /etc/zsh_command_not_found ]

echo "[*] Registering shells idempotently in /etc/shells..."
for s in /bin/zsh /usr/bin/zsh; do
    if ! remote_exec grep -qxF "$s" /etc/shells; then
        echo "$s" | remote_sudo tee -a /etc/shells >/dev/null
    fi
done

echo "[*] Configuring system zprofile login chain..."
if remote_exec [ -f /etc/zsh/zprofile ]; then
    if ! remote_exec grep -q "emulate sh -c" /etc/zsh/zprofile; then
        echo "emulate sh -c '. /etc/profile'" | remote_sudo tee -a /etc/zsh/zprofile >/dev/null
    fi
fi

echo "[*] Deploying /etc/skel/ templates..."
scp "${SCP_OPTS[@]}" "$LOCAL_STAGING/.zshrc" "$TARGET_ALIAS:$REMOTE_STAGING/skel/.zshrc"
scp "${SCP_OPTS[@]}" "$LOCAL_STAGING/.zprofile" "$TARGET_ALIAS:$REMOTE_STAGING/skel/.zprofile"
remote_sudo install -m 0644 -o root -g root "$REMOTE_STAGING/skel/.zshrc" /etc/skel/.zshrc
remote_sudo install -m 0644 -o root -g root "$REMOTE_STAGING/skel/.zprofile" /etc/skel/.zprofile

echo "[*] Setting default shell for future accounts in useradd and adduser.conf..."
remote_sudo sed -i 's|^SHELL=.*|SHELL=/bin/zsh|' /etc/default/useradd
remote_sudo sed -i 's|^[#]*[[:space:]]*DSHELL=.*|DSHELL=/bin/zsh|' /etc/adduser.conf

echo "[*] Processing user profiles, backups, and customization migration..."
for u in $DISCOVERED_USERS; do
    u_home=$(remote_exec getent passwd "$u" | cut -d: -f6)
    u_group=$(remote_exec id -gn "$u")
    prev_shell=$(remote_exec getent passwd "$u" | cut -d: -f7)

    echo "[*] Backing up user profile for $u..."
    u_backup="$u_home/.zsh-backup-$TS"
    remote_sudo mkdir -p "$u_backup"
    remote_sudo chown "$u:$u_group" "$u_backup"
    
    if ! remote_exec [ -e "$u_home/.zsh-backup-baseline" ]; then
        remote_sudo cp -a "$u_home" "$u_backup/baseline" 2>/dev/null || true
        remote_sudo ln -s "$u_backup" "$u_home/.zsh-backup-baseline"
        remote_sudo chown -h "$u:$u_group" "$u_home/.zsh-backup-baseline"
    fi
    remote_sudo rm -f "$u_home/.zsh-backup-latest"
    remote_sudo ln -s "$u_backup" "$u_home/.zsh-backup-latest"
    remote_sudo chown -h "$u:$u_group" "$u_home/.zsh-backup-latest"

    for f in .bashrc .bash_aliases .profile .zshrc .zprofile .zshenv; do
        if remote_exec [ -f "$u_home/$f" ]; then
            remote_sudo cp -p "$u_home/$f" "$u_backup/"
        fi
    done

    # Generate user restore script
    remote_sudo tee "$u_backup/restore-user.sh" >/dev/null <<EOF
#!/usr/bin/env bash
set -euo pipefail
echo "[*] Restoring user $u configuration..."
for f in .bashrc .bash_aliases .profile .zshrc .zprofile .zshenv; do
    if [ -f "$u_backup/\$f" ]; then
        cp -p "$u_backup/\$f" "$u_home/\$f"
    fi
done
sudo chsh -s "$prev_shell" "$u"
echo "[+] User $u restore completed."
EOF
    remote_sudo chmod +x "$u_backup/restore-user.sh"
    remote_sudo chown "$u:$u_group" "$u_backup/restore-user.sh"

    # Harvest custom additions from .bashrc and .bash_aliases
    migrated_block=""
    if remote_exec [ -f "$u_home/.bashrc" ]; then
        # Simple harvesting of non-comment, non-skel lines
        migrated_block=$(remote_exec awk '
            NR==FNR { skel[$0]=1; next }
            !($0 in skel) && $0 !~ /^[[:space:]]*#/ && $0 !~ /^[[:space:]]*$/ { print }
        ' /etc/skel/.bashrc "$u_home/.bashrc" || true)
    fi
    if remote_exec [ -f "$u_home/.bash_aliases" ]; then
        aliases_content=$(remote_exec cat "$u_home/.bash_aliases")
        migrated_block="${migrated_block:+$migrated_block\n}$aliases_content"
    fi

    echo "[*] Constructing personalized .zshrc for $u..."
    target_zshrc="$u_home/.zshrc"
    if remote_exec [ -L "$u_home/.zshrc" ]; then
        target_zshrc=$(remote_exec readlink -f "$u_home/.zshrc")
    fi

    # Staging personalized zshrc
    remote_exec mkdir -p "$REMOTE_STAGING/users/$u"
    
    # Base skel zshrc + migration block
    remote_exec cp "$LOCAL_STAGING/.zshrc" "$REMOTE_STAGING/users/$u/.zshrc"
    
    {
        echo ""
        echo "# >>> kali-zsh-setup: migrated user config >>>"
        if [ "$USE_KALI_PATH" -eq 1 ] && [ -n "$KALI_LOGIN_PATH" ]; then
            sanitized_path=""
            for d in $(echo "$KALI_LOGIN_PATH" | tr ':' ' '); do
                if remote_exec [ -d "$d" ]; then
                    if [ "$u" = "root" ] && echo "$d" | grep -q '^/home/'; then
                        continue
                    fi
                    sanitized_path="${sanitized_path:+$sanitized_path:}$d"
                fi
            done
            if [ -n "$sanitized_path" ]; then
                echo "export PATH=\"$sanitized_path:\$PATH\""
            fi
        fi
        if [ -n "$migrated_block" ]; then
            echo -e "$migrated_block"
        fi
        echo "# <<< kali-zsh-setup: migrated user config <<<"
    } | remote_exec tee -a "$REMOTE_STAGING/users/$u/.zshrc" >/dev/null

    scp "${SCP_OPTS[@]}" "$LOCAL_STAGING/.zprofile" "$TARGET_ALIAS:$REMOTE_STAGING/users/$u/.zprofile"

    # Atomically install dotfiles
    remote_sudo install -m 0644 -o "$u" -g "$u_group" "$REMOTE_STAGING/users/$u/.zshrc" "$target_zshrc"
    remote_sudo install -m 0644 -o "$u" -g "$u_group" "$REMOTE_STAGING/users/$u/.zprofile" "$u_home/.zprofile"
done

echo "[*] Running pre-switch validation gate for all profiles..."
for u in $DISCOVERED_USERS; do
    u_home=$(remote_exec getent passwd "$u" | cut -d: -f6)
    val_err=$(mktemp)
    
    echo "[*] Validating zsh environment for $u..."
    set +e
    remote_sudo -u "$u" -H timeout --kill-after=5s 15s env TERM=xterm-256color sh -c "cd '$u_home' && zsh -l -i -c 'autoload -Uz compinit && compinit -u && bindkey -e && [[ -n \$ZSH_HIGHLIGHT_VERSION ]] && exit 0'" 2> "$val_err"
    val_rc=$?
    set -e

    if [ "$val_rc" -eq 124 ]; then
        echo "[!] FATAL: Validation timed out for user $u (VALIDATION_TIMEOUT)." >&2
        exit 1
    elif [ "$val_rc" -ne 0 ]; then
        echo "[!] FATAL: Validation failed for user $u (rc: $val_rc). Stderr output:" >&2
        cat "$val_err" >&2
        rm -f "$val_err"
        exit 1
    fi
    rm -f "$val_err"
done

echo "[*] Executing break-glass shell switch..."
# Non-root switch first
for u in $DISCOVERED_USERS; do
    if [ "$u" != "root" ]; then
        echo "[*] Switching login shell for user $u to /bin/zsh..."
        remote_sudo chsh -s /bin/zsh "$u"
        new_shell=$(remote_exec getent passwd "$u" | cut -d: -f7)
        [ "$new_shell" = "/bin/zsh" ] || { echo "[!] Failed to switch shell for $u" >&2; exit 1; }
    fi
done

# Root switch gate & verification
if echo "$DISCOVERED_USERS" | grep -qw "root"; then
    echo "[*] Verifying root login capability before switch..."
    remote_sudo -u root -H env TERM=xterm-256color sh -c 'zsh -l -i -c "exit 0"' || {
        echo "[!] Root pre-switch validation failed." >&2
        exit 1
    }

    echo "[*] Switching root login shell to /bin/zsh..."
    root_prev_shell=$(remote_exec getent passwd root | cut -d: -f7)
    remote_sudo chsh -s /bin/zsh root

    echo "[*] Verifying root post-switch login shell..."
    root_new_shell=$(remote_exec getent passwd root | cut -d: -f7)
    if [ "$root_new_shell" != "/bin/zsh" ] || ! remote_sudo -i -u root env TERM=xterm-256color zsh -l -i -c 'exit 0'; then
        echo "[!] CRITICAL: Root shell verification failed! Rolling back root shell immediately..." >&2
        remote_sudo chsh -s "$root_prev_shell" root
        exit 1
    fi
fi

echo "[*] Running post-install smoke tests..."
# Smoke test for non-root user sippo
if remote_exec id sippo >/dev/null 2>&1; then
    remote_exec su -l sippo -c 'zsh -i -c "print -r -- $PROMPT"' || echo "[!] Warning: sippo smoke test output check failed"
fi

# Smoke test for root
remote_sudo -u root -H env TERM=xterm-256color sh -c 'zsh -l -i -c "print -r -- \$PROMPT"' || echo "[!] Warning: root smoke test output check failed"

echo "[+] Kali-identical zsh deployment completed successfully across all profiles!"
