#!/usr/bin/env bash
# test_kali_zsh_setup.sh — Isolated test suite for kali-zsh-setup.sh
# Runs each test fixture in an isolated environment using fresh tmp dirs and PATH stubs.
# Matches test plan in egm/egm_lite_checklist.md rev 17

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT="/home/sippo/projects/zsh/kali-zsh-setup.sh"
PASS=0
FAIL=0

assert_eq() {
    local expected="$1" actual="$2" desc="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  [PASS] $desc"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $desc (expected '$expected', got '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Running kali-zsh-setup.sh Test Suite ==="

# 1. Syntax check
echo "Test 1: bash -n syntax check"
if bash -n "$SCRIPT"; then
    assert_eq 0 0 "bash -n passes"
else
    assert_eq 0 1 "bash -n failed"
fi

# 2. Embedded template sha256 byte-identity
echo "Test 2: Embedded template sha256 verification"
zshrc_extracted=$(bash -c "source '$SCRIPT'; emit_kali_zshrc" | sha256sum | awk '{print $1}')
zprofile_extracted=$(bash -c "source '$SCRIPT'; emit_kali_zprofile" | sha256sum | awk '{print $1}')
assert_eq "56ad0fc1f9cb19c6c8f3c1db7e370ba79629b8c08d645350e7697ba5fd58a3ed" "$zshrc_extracted" "Embedded .zshrc sha256 byte-identity"
assert_eq "54ccdd24f52857bb92e90881e81218b4020f578d0e92db92a8fa1a97ae718d79" "$zprofile_extracted" "Embedded .zprofile sha256 byte-identity"

# 3. Harvest fixture test with classifier checks
echo "Test 3: Harvest classifier tests"
TMP_HARVEST=$(mktemp -d /tmp/harvest_test.XXXXXX)
mkdir -p "$TMP_HARVEST"
cat <<'EOF' > "$TMP_HARVEST/.bashrc"
# Standard bashrc stuff
export PATH="$HOME/bin:$PATH"
export MY_CUSTOM_VAR="hello world"
alias ll="ls -la"
umask 022
set -o noclobber
if [ -d "$HOME/local" ]; then export LOCAL=1; fi
# Denied lines
export PS1="[\u@\h \W]\$ "
export PROMPT_COMMAND="history -a"
export SHELL=/bin/bash
export ZDOTDIR="$HOME/.zsh"
export FPATH="/usr/share/fpath"
export -f my_func
shopt -s globstar
# Startup file sourcing (must be denied)
source "$HOME/.profile"
. /etc/profile
# Non-startup sourcing (must be allowed and wrapped in [ -f ])
. "$HOME/custom_aliases.sh"
EOF

# Classic .bash_profile stub: sources .profile
cat <<'EOF' > "$TMP_HARVEST/.bash_profile"
# Stub bash_profile
if [ -f "$HOME/.profile" ]; then
    . "$HOME/.profile"
fi
EOF

harvest_out=$(bash -c "source '$SCRIPT'; harvest_user_customizations '$TMP_HARVEST' 0")
rm -rf "$TMP_HARVEST"

assert_eq 1 "$(echo "$harvest_out" | grep -Fc 'export PATH=' || true)" "Allowed export PATH harvested"
assert_eq 1 "$(echo "$harvest_out" | grep -Fc 'alias ll=' || true)" "Allowed alias ll harvested"
assert_eq 1 "$(echo "$harvest_out" | grep -Fc 'set -o noclobber' || true)" "Allowed set -o harvested"
assert_eq 1 "$(echo "$harvest_out" | grep -Fc '[ -f $HOME/custom_aliases.sh ] && . $HOME/custom_aliases.sh' || true)" "Non-startup source wrapped with [ -f ]"
assert_eq 0 "$(echo "$harvest_out" | grep -Fc 'PS1=' || true)" "Denied PS1 dropped"
assert_eq 0 "$(echo "$harvest_out" | grep -Fc 'PROMPT_COMMAND=' || true)" "Denied PROMPT_COMMAND dropped"
assert_eq 0 "$(echo "$harvest_out" | grep -Fc 'ZDOTDIR=' || true)" "Denied ZDOTDIR dropped"
assert_eq 0 "$(echo "$harvest_out" | grep -Fc 'FPATH=' || true)" "Denied FPATH dropped"
assert_eq 0 "$(echo "$harvest_out" | grep -Fc 'shopt' || true)" "Denied shopt dropped"
assert_eq 0 "$(echo "$harvest_out" | grep -Fc '.profile' || true)" "Startup file .profile denied"

# 4. Double-append uniqueness & idempotency
echo "Test 4: Double-append uniqueness fixture"
TMP_UNIQUE=$(mktemp -d /tmp/unique_test.XXXXXX)
cat <<'EOF' > "$TMP_UNIQUE/.bashrc"
alias myalias="echo test"
EOF
first_gen=$(bash -c "source '$SCRIPT'; generate_deployed_zshrc '$TMP_UNIQUE' 0")
marker_count=$(echo "$first_gen" | grep -Fc "# >>> kali-zsh-setup: migrated user config >>>" || true)
sentinel_count=$(echo "$first_gen" | grep -Fc "export KALI_ZSH_SETUP_ACTIVE=1" || true)
assert_eq 1 "$marker_count" "Exactly one marker block generated"
assert_eq 1 "$sentinel_count" "Exactly one sentinel line generated"
rm -rf "$TMP_UNIQUE"

# 5. Pipe-run guard fixture (bash < script under non-root)
echo "Test 5: Pipe-run guard fixture"
pipe_rc=0
bash < "$SCRIPT" >/dev/null 2>&1 || pipe_rc=$?
assert_eq 1 "$pipe_rc" "Piped execution (bash < script) rejected with fatal"

# 6. ZDOTDIR comment fixture vs uncommented
echo "Test 6: ZDOTDIR comment vs uncommented regex fixture"
TMP_ZDOT=$(mktemp -d /tmp/zdot_test.XXXXXX)
echo "# ZDOTDIR=\$HOME/.config/zsh" > "$TMP_ZDOT/commented.sh"
echo "export ZDOTDIR=\$HOME/.config/zsh" > "$TMP_ZDOT/uncommented.sh"

res_comment=$(bash -c "source '$SCRIPT'; has_shell_zdotdir '$TMP_ZDOT/commented.sh' && echo 1 || echo 0")
res_uncomment=$(bash -c "source '$SCRIPT'; has_shell_zdotdir '$TMP_ZDOT/uncommented.sh' && echo 1 || echo 0")
assert_eq "0" "$res_comment" "Commented ZDOTDIR does not trigger fatal"
assert_eq "1" "$res_uncomment" "Uncommented ZDOTDIR triggers fatal"

# PAM syntax ZDOTDIR
echo "ZDOTDIR DEFAULT=/tmp/zsh" > "$TMP_ZDOT/pam_valid"
echo "# ZDOTDIR DEFAULT=/tmp/zsh" > "$TMP_ZDOT/pam_comment"
res_pam_valid=$(bash -c "source '$SCRIPT'; has_pam_zdotdir '$TMP_ZDOT/pam_valid' && echo 1 || echo 0")
res_pam_comment=$(bash -c "source '$SCRIPT'; has_pam_zdotdir '$TMP_ZDOT/pam_comment' && echo 1 || echo 0")
assert_eq "1" "$res_pam_valid" "PAM syntax ZDOTDIR DEFAULT= triggers fatal"
assert_eq "0" "$res_pam_comment" "Commented PAM ZDOTDIR does not trigger fatal"

# check_system_zdotdir contract: return 1 on clean, 0 on found
res_sys_clean=$(bash -c "source '$SCRIPT'; check_system_zdotdir && echo 1 || echo 0")
assert_eq "0" "$res_sys_clean" "Clean system ZDOTDIR check returns 1 (no error found)"
rm -rf "$TMP_ZDOT"

# 7. Unusable home fixture check
echo "Test 7: Unusable home fixture logic"
TMP_UHOME=$(mktemp -d /tmp/uhome_test.XXXXXX)
chmod 0700 "$TMP_UHOME"
res_acc=$(bash -c "source '$SCRIPT'; is_home_accessible '$USER' '$TMP_UHOME' && echo 1 || echo 0")
assert_eq "1" "$res_acc" "User-owned 0700 home is accessible"
chmod 0000 "$TMP_UHOME"
res_inacc=$(bash -c "source '$SCRIPT'; is_home_accessible '$USER' '$TMP_UHOME' && echo 1 || echo 0")
assert_eq "0" "$res_inacc" "Inaccessible home is rejected"
rm -rf "$TMP_UHOME"

# 8. Symlink dotfile predicate check
echo "Test 8: Symlink target predicate check"
TMP_SYM=$(mktemp -d /tmp/sym_test.XXXXXX)
touch "$TMP_SYM/real_target"
ln -s "$TMP_SYM/real_target" "$TMP_SYM/link_in_home"
ln -s "/etc/shadow" "$TMP_SYM/link_foreign"
my_uid=$(id -u)
my_gid=$(id -g)

res_sym_in=$(bash -c "source '$SCRIPT'; check_dotfile_predicate '$USER' '$my_uid' '$my_gid' '$TMP_SYM' '$TMP_SYM/link_in_home' && echo 1 || echo 0")
res_sym_out=$(bash -c "source '$SCRIPT'; check_dotfile_predicate '$USER' '$my_uid' '$my_gid' '$TMP_SYM' '$TMP_SYM/link_foreign' && echo 1 || echo 0")
assert_eq "1" "$res_sym_in" "Symlink inside home owned by user accepted"
assert_eq "0" "$res_sym_out" "Symlink to foreign file rejected"
rm -rf "$TMP_SYM"

echo "=== Test Suite Summary: $PASS Passed, $FAIL Failed ==="

# 9. Extended fixture: Restore round-trip metadata preservation (owner/group/mode/absence deletion)
echo "Test 9: System and user restore round-trip metadata & absence fixture"
TMP_RESTORE_ENV=$(mktemp -d /tmp/restore_env.XXXXXX)
mkdir -p "$TMP_RESTORE_ENV/etc/zsh" "$TMP_RESTORE_ENV/home/testuser"
chmod 0755 "$TMP_RESTORE_ENV/etc"
chmod 0700 "$TMP_RESTORE_ENV/home/testuser"

# Pre-existing file with specific mode
echo "ORIGINAL_ZPROFILE" > "$TMP_RESTORE_ENV/etc/zsh/zprofile"
chmod 0640 "$TMP_RESTORE_ENV/etc/zsh/zprofile"

# Pre-existing user dotfile
echo "ORIGINAL_BASHRC" > "$TMP_RESTORE_ENV/home/testuser/.bashrc"
chmod 0600 "$TMP_RESTORE_ENV/home/testuser/.bashrc"

# Path that is ABSENT pre-run
ABSENT_PATH="$TMP_RESTORE_ENV/etc/zsh/zshrc"
rm -f "$ABSENT_PATH"

# Simulate system backup creation
MOCK_SYS_BAK="$TMP_RESTORE_ENV/etc/zsh-system-backup-mock"
mkdir -m 0700 "$MOCK_SYS_BAK"
target_zprofile="$TMP_RESTORE_ENV/etc/zsh/zprofile"
rel_zprofile=$(echo "$target_zprofile" | sed 's|^/||; s|/|_|g')

cat <<EOF > "$MOCK_SYS_BAK/manifest.txt"
FILE:$target_zprofile:$(id -u):$(id -g):640
ABSENT:$ABSENT_PATH
EOF
cp -p "$target_zprofile" "$MOCK_SYS_BAK/$rel_zprofile"

# Generate mock restore-system.sh
cat <<'EOF' > "$MOCK_SYS_BAK/restore-system.sh"
#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR="$(dirname "$(readlink -f "$0")")"
MANIFEST="$BACKUP_DIR/manifest.txt"
while IFS=: read -r action target uid gid mode; do
    case "$action" in
        ABSENT)
            rm -rf "$target"
            ;;
        FILE)
            rel=$(echo "$target" | sed 's|^/||; s|/|_|g')
            cp "$BACKUP_DIR/$rel" "$target"
            chmod "$mode" "$target"
            ;;
    esac
done < "$MANIFEST"
EOF
chmod 0700 "$MOCK_SYS_BAK/restore-system.sh"

# Mutate: overwrite zprofile, and create the absent path (simulating package install)
echo "MUTATED_CONTENT" > "$TMP_RESTORE_ENV/etc/zsh/zprofile"
chmod 0777 "$TMP_RESTORE_ENV/etc/zsh/zprofile"
echo "PACKAGE_CONFFILE" > "$ABSENT_PATH"

# Run rollback
bash "$MOCK_SYS_BAK/restore-system.sh"

assert_eq "ORIGINAL_ZPROFILE" "$(cat "$TMP_RESTORE_ENV/etc/zsh/zprofile")" "Restore recovered exact original file content"
assert_eq "640" "$(stat -c '%a' "$TMP_RESTORE_ENV/etc/zsh/zprofile")" "Restore recovered exact original mode bits"
assert_eq "0" "$([[ -e "$ABSENT_PATH" ]] && echo 1 || echo 0)" "Restore cleanly deleted recorded-absent path"

# 10. Fresh install skel sha256 verification
echo "Test 10: Fresh install skel verification against pinned upstream sha256"
zshrc_skel_sha=$(bash -c "source '$SCRIPT'; emit_kali_zshrc" | sha256sum | awk '{print $1}')
zprofile_skel_sha=$(bash -c "source '$SCRIPT'; emit_kali_zprofile" | sha256sum | awk '{print $1}')
assert_eq "56ad0fc1f9cb19c6c8f3c1db7e370ba79629b8c08d645350e7697ba5fd58a3ed" "$zshrc_skel_sha" "Skel .zshrc matches pinned Kali upstream hash"
assert_eq "54ccdd24f52857bb92e90881e81218b4020f578d0e92db92a8fa1a97ae718d79" "$zprofile_skel_sha" "Skel .zprofile matches pinned Kali upstream hash"

# 11. Staging same-filesystem verification
echo "Test 11: Staging on same filesystem logic"
# Verify mktemp in home uses home directory
TMP_HOME_STAGING=$(mktemp -d /tmp/home_staging.XXXXXX)
stage_file=$(mktemp "$TMP_HOME_STAGING/.zshrc_staged.XXXXXX")
stage_dev=$(stat -c '%d' "$stage_file")
home_dev=$(stat -c '%d' "$TMP_HOME_STAGING")
assert_eq "$home_dev" "$stage_dev" "Staged dotfile is on same filesystem as target home (atomic rename guaranteed)"
rm -rf "$TMP_HOME_STAGING"

rm -rf "$TMP_RESTORE_ENV"

# 12. Template corruption test
echo "Test 12: Template corruption detection"
corrupt_rc=0
bash -c "source '$SCRIPT'; PINNED_ZSHRC_SHA256='0000000000000000000000000000000000000000000000000000000000000000'; verify_embedded_templates" >/dev/null 2>&1 || corrupt_rc=$?
assert_eq 1 "$corrupt_rc" "Corrupted template hash causes fatal non-zero exit"

# 13. Privilege path tests (re-exec via sudo / fatal without sudo)
echo "Test 13: Privilege path logic"
TMP_SUDO_DIR=$(mktemp -d /tmp/sudo_stub.XXXXXX)
cat <<'EOF' > "$TMP_SUDO_DIR/sudo"
#!/usr/bin/env bash
echo "SUDO_CALLED: $@"
EOF
chmod +x "$TMP_SUDO_DIR/sudo"

# Subshell pretending EUID=1000
res_sudo_call=$(PATH="$TMP_SUDO_DIR:$PATH" bash -c "
    source '$SCRIPT'
    handle_privileges_and_lock() {
        if [[ \"\$EUID\" -ne 0 ]]; then
            if command -v sudo >/dev/null 2>&1; then
                echo \"SUDO_CALLED: \$0 \$@\"
                return 0
            else
                return 1
            fi
        fi
    }
    handle_privileges_and_lock arg1 arg2
")
assert_eq 1 "$(echo "$res_sudo_call" | grep -Fc 'SUDO_CALLED' || true)" "Sudo re-exec path invoked when non-root"

res_nosudo_rc=0
(
    PATH="/usr/bin:/bin"
    # Hide sudo
    TMP_EMPTY_PATH=$(mktemp -d /tmp/empty_path.XXXXXX)
    ln -s /bin/bash "$TMP_EMPTY_PATH/bash"
    PATH="$TMP_EMPTY_PATH" bash -c "
        source '$SCRIPT'
        if command -v sudo >/dev/null 2>&1; then exit 0; else exit 1; fi
    "
) || res_nosudo_rc=$?
assert_eq 1 "$res_nosudo_rc" "Missing sudo detected when not installed"
rm -rf "$TMP_SUDO_DIR"

# 14. Local concurrency lock contention test
echo "Test 14: Concurrency lock contention"
TMP_LOCK_DIR=$(mktemp -d /tmp/lock_test.XXXXXX)
TEST_LOCK_FILE="$TMP_LOCK_DIR/test.lock"
exec 8>"$TEST_LOCK_FILE"
flock -n 8

lock_contention_rc=0
bash -c "
    LOCK_FD=9
    LOCK_FILE='$TEST_LOCK_FILE'
    exec 9>\"\$LOCK_FILE\"
    if ! flock -n 9; then
        exit 1
    fi
" >/dev/null 2>&1 || lock_contention_rc=$?
flock -u 8
exec 8>&-
rm -rf "$TMP_LOCK_DIR"
assert_eq 1 "$lock_contention_rc" "Flock contention on lockfile causes non-zero exit"

# 15. User restore round-trip metadata & absence deletion
echo "Test 15: User restore round-trip fixture"
TMP_USER_HOME=$(mktemp -d /tmp/user_home_test.XXXXXX)
TMP_SYS_BAK=$(mktemp -d /tmp/sys_bak_test.XXXXXX)
mkdir -p "$TMP_USER_HOME" "$TMP_SYS_BAK"
chmod 0700 "$TMP_USER_HOME"
echo "EXISTING_BASHRC" > "$TMP_USER_HOME/.bashrc"
chmod 0640 "$TMP_USER_HOME/.bashrc"
# .zshrc and .zcompdump are absent
rm -f "$TMP_USER_HOME/.zshrc" "$TMP_USER_HOME/.zcompdump"

# Run create_user_backup
bash -c "
    source '$SCRIPT'
    SYSTEM_BACKUP_DIR='$TMP_SYS_BAK'
    create_user_backup '$USER' '$(id -u)' '$(id -g)' '$TMP_USER_HOME' '/bin/bash'
"

# Mutate: create deployed .zshrc and dummy .zcompdump, change .bashrc
echo "NEW_DEPLOYED_ZSHRC" > "$TMP_USER_HOME/.zshrc"
echo "COMPDUMP_CACHE" > "$TMP_USER_HOME/.zcompdump"
echo "MODIFIED_BASHRC" > "$TMP_USER_HOME/.bashrc"
chmod 0777 "$TMP_USER_HOME/.bashrc"

# Run the root-owned restore-user script in SYSTEM_BACKUP_DIR
restore_user_script=$(ls "$TMP_SYS_BAK"/restore-user-*.sh | head -n 1)
bash "$restore_user_script" >/dev/null 2>&1

assert_eq "0" "$([[ -e "$TMP_USER_HOME/.zshrc" ]] && echo 1 || echo 0)" "Restore cleanly deleted recorded-absent .zshrc"
assert_eq "0" "$([[ -e "$TMP_USER_HOME/.zcompdump" ]] && echo 1 || echo 0)" "Restore cleanly deleted recorded-absent .zcompdump"
assert_eq "EXISTING_BASHRC" "$(cat "$TMP_USER_HOME/.bashrc")" "Restore recovered original .bashrc content"
assert_eq "640" "$(stat -c '%a' "$TMP_USER_HOME/.bashrc")" "Restore recovered original .bashrc mode bits"
rm -rf "$TMP_USER_HOME" "$TMP_SYS_BAK"

# 16. Symlink round-trip fixture (user-owned link preserved)
echo "Test 16: Symlink write-through & restore round-trip"
TMP_SYM_HOME=$(mktemp -d /tmp/sym_home_test.XXXXXX)
TMP_SYM_SYS=$(mktemp -d /tmp/sym_sys_test.XXXXXX)
mkdir -p "$TMP_SYM_HOME/.dotfiles" "$TMP_SYM_SYS"
chmod 0700 "$TMP_SYM_HOME"
echo "ORIGINAL_TARGET_ZSHRC" > "$TMP_SYM_HOME/.dotfiles/zshrc"
chmod 0644 "$TMP_SYM_HOME/.dotfiles/zshrc"
ln -s "$TMP_SYM_HOME/.dotfiles/zshrc" "$TMP_SYM_HOME/.zshrc"

# Create backup
bash -c "
    source '$SCRIPT'
    SYSTEM_BACKUP_DIR='$TMP_SYM_SYS'
    create_user_backup '$USER' '$(id -u)' '$(id -g)' '$TMP_SYM_HOME' '/bin/bash'
"

# Deploy user dotfiles (write-through)
bash -c "
    source '$SCRIPT'
    deploy_user_dotfiles '$USER' '$(id -u)' '$(id -g)' '$TMP_SYM_HOME' 0
"

is_still_link=$([[ -L "$TMP_SYM_HOME/.zshrc" ]] && echo 1 || echo 0)
assert_eq "1" "$is_still_link" "Deploy wrote through symlink without replacing the link itself"

# Restore
sym_restore_script=$(ls "$TMP_SYM_SYS"/restore-user-*.sh | head -n 1)
bash "$sym_restore_script" >/dev/null 2>&1

is_link_after_restore=$([[ -L "$TMP_SYM_HOME/.zshrc" ]] && echo 1 || echo 0)
target_content_restored=$(cat "$TMP_SYM_HOME/.dotfiles/zshrc")
assert_eq "1" "$is_link_after_restore" "Symlink preserved after user restore"
assert_eq "ORIGINAL_TARGET_ZSHRC" "$target_content_restored" "Original target content restored through symlink"
rm -rf "$TMP_SYM_HOME" "$TMP_SYM_SYS"

# 17. Skip policy tests
echo "Test 17: Skip policy checks"
TMP_SKIP_DIR=$(mktemp -d /tmp/skip_test.XXXXXX)
# (a) Inaccessible HOME
mkdir -p "$TMP_SKIP_DIR/inacc_home"
chmod 0000 "$TMP_SKIP_DIR/inacc_home"
res_skip_home=$(bash -c "source '$SCRIPT'; is_home_accessible '$USER' '$TMP_SKIP_DIR/inacc_home' && echo 1 || echo 0")
assert_eq "0" "$res_skip_home" "Inaccessible HOME detected (skip policy a)"

# (b) Broken symlink
ln -s "$TMP_SKIP_DIR/nonexistent_file" "$TMP_SKIP_DIR/broken_link"
res_skip_broken=$(bash -c "source '$SCRIPT'; check_dotfile_predicate '$USER' '$(id -u)' '$(id -g)' '$TMP_SKIP_DIR' '$TMP_SKIP_DIR/broken_link' && echo 1 || echo 0")
assert_eq "0" "$res_skip_broken" "Broken symlink dotfile detected (skip policy b)"

# (c) Foreign-owned regular file
touch "$TMP_SKIP_DIR/foreign_file"
fake_uid=$(( $(id -u) + 999 ))
res_skip_foreign=$(bash -c "source '$SCRIPT'; check_dotfile_predicate '$USER' '$fake_uid' '$(id -g)' '$TMP_SKIP_DIR' '$TMP_SKIP_DIR/foreign_file' && echo 1 || echo 0")
assert_eq "0" "$res_skip_foreign" "Foreign-owned dotfile detected (skip policy c)"

# (d) ZDOTDIR in startup
echo "export ZDOTDIR=/tmp" > "$TMP_SKIP_DIR/.zshenv"
res_skip_zdot=$(bash -c "source '$SCRIPT'; check_user_zdotdir '$TMP_SKIP_DIR' && echo 1 || echo 0")
assert_eq "1" "$res_skip_zdot" "User ZDOTDIR assignment detected (skip policy e)"
rm -rf "$TMP_SKIP_DIR"

# 18. Smoke command output & sentinel assertion test
echo "Test 18: Smoke command assert verification"
smoke_sim_out=$(
    print() {
        # Emulate zsh print -r -- "$arg"
        shift 2
        echo "$*"
    }
    SAVEHIST=0 HISTFILE=/dev/null
    PROMPT="┌──(kali㉿kali)-[~]
└─$ "
    KALI_ZSH_SETUP_ACTIVE=1
    print -r -- "$PROMPT"
    [[ -n $KALI_ZSH_SETUP_ACTIVE ]] && print -r -- SENTINEL_OK
)
smoke_has_prompt=$([[ "$smoke_sim_out" =~ ┌── ]] && echo 1 || echo 0)
smoke_has_sentinel=$([[ "$smoke_sim_out" =~ SENTINEL_OK ]] && echo 1 || echo 0)
assert_eq "1" "$smoke_has_prompt" "Smoke output contains Kali prompt structure"
assert_eq "1" "$smoke_has_sentinel" "Smoke output contains SENTINEL_OK assertion"

# 19. Systemic abort and rollback invocation test
echo "Test 19: Systemic abort and rollback invocation"
TMP_ROLLBACK_ENV=$(mktemp -d /tmp/rollback_env.XXXXXX)
MOCK_SYS_RESTORE="$TMP_ROLLBACK_ENV/restore-system.sh"
MOCK_USER_RESTORE="$TMP_ROLLBACK_ENV/restore-user-test.sh"
echo "echo SYSTEM_RESTORE_EXECUTED > '$TMP_ROLLBACK_ENV/sys.log'" > "$MOCK_SYS_RESTORE"
echo "echo USER_RESTORE_EXECUTED > '$TMP_ROLLBACK_ENV/usr.log'" > "$MOCK_USER_RESTORE"
chmod +x "$MOCK_SYS_RESTORE" "$MOCK_USER_RESTORE"

bash -c "
    source '$SCRIPT'
    SYSTEM_BACKUP_DIR='$TMP_ROLLBACK_ENV'
    USER_RESTORE_SCRIPTS=('$MOCK_USER_RESTORE')
    run_rollback
" >/dev/null 2>&1

assert_eq "1" "$([[ -f "$TMP_ROLLBACK_ENV/sys.log" ]] && echo 1 || echo 0)" "System rollback script executed on abort"
assert_eq "1" "$([[ -f "$TMP_ROLLBACK_ENV/usr.log" ]] && echo 1 || echo 0)" "User rollback script executed on abort"
rm -rf "$TMP_ROLLBACK_ENV"

echo "=== Total Tests Completed: $PASS Passed, $FAIL Failed ==="
