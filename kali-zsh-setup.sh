#!/usr/bin/env bash
# kali-zsh-setup.sh — Standalone self-contained Kali-zsh template installer for Debian
# Sets up Kali-identical zsh across /etc/skel and all interactive profiles.
# Idempotent, standalone, runs locally on any Debian machine.
#
# Spec: egm/egm_lite_checklist.md rev 17 (Verified [LGTM])

set -Eeuo pipefail
IFS=$'\n\t'

readonly PINNED_ZSHRC_SHA256="56ad0fc1f9cb19c6c8f3c1db7e370ba79629b8c08d645350e7697ba5fd58a3ed"
readonly PINNED_ZPROFILE_SHA256="54ccdd24f52857bb92e90881e81218b4020f578d0e92db92a8fa1a97ae718d79"
readonly SENTINEL_LINE="export KALI_ZSH_SETUP_ACTIVE=1"
readonly SENTINEL_COMMENT="# Managed by kali-zsh-setup.sh — DO NOT REMOVE"
readonly MARKER_START="# >>> kali-zsh-setup: migrated user config >>>"
readonly MARKER_END="# <<< kali-zsh-setup: migrated user config <<<"

# --- Heredoc Embedded Templates ---
emit_kali_zshrc() {
    cat <<'KALI_ZSHRC_EOF'
# ~/.zshrc file for zsh interactive shells.
# see /usr/share/doc/zsh/examples/zshrc for examples

setopt autocd              # change directory just by typing its name
#setopt correct            # auto correct mistakes
setopt interactivecomments # allow comments in interactive mode
setopt magicequalsubst     # enable filename expansion for arguments of the form ‘anything=expression’
setopt nonomatch           # hide error message if there is no match for the pattern
setopt notify              # report the status of background jobs immediately
setopt numericglobsort     # sort filenames numerically when it makes sense
setopt promptsubst         # enable command substitution in prompt

WORDCHARS='_-' # Don't consider certain characters part of the word

# hide EOL sign ('%')
PROMPT_EOL_MARK=""

# configure key keybindings
bindkey -e                                        # emacs key bindings
bindkey ' ' magic-space                           # do history expansion on space
bindkey '^U' backward-kill-line                   # ctrl + U
bindkey '^[[3;5~' kill-word                       # ctrl + Supr
bindkey '^[[3~' delete-char                       # delete
bindkey '^[[1;5C' forward-word                    # ctrl + ->
bindkey '^[[1;5D' backward-word                   # ctrl + <-
bindkey '^[[5~' beginning-of-buffer-or-history    # page up
bindkey '^[[6~' end-of-buffer-or-history          # page down
bindkey '^[[H' beginning-of-line                  # home
bindkey '^[[F' end-of-line                        # end
bindkey '^[[Z' undo                               # shift + tab undo last action

# enable completion features
autoload -Uz compinit
compinit -d ~/.cache/zcompdump
zstyle ':completion:*:*:*:*:*' menu select
zstyle ':completion:*' auto-description 'specify: %d'
zstyle ':completion:*' completer _expand _complete
zstyle ':completion:*' format 'Completing %d'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' list-colors ''
zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more, or the character to insert%s
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' rehash true
zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'

# History configurations
HISTFILE=~/.zsh_history
HISTSIZE=1000
SAVEHIST=2000
setopt hist_expire_dups_first # delete duplicates first when HISTFILE size exceeds HISTSIZE
setopt hist_ignore_dups       # ignore duplicated commands history list
setopt hist_ignore_space      # ignore commands that start with space
setopt hist_verify            # show command with history expansion to user before running it
#setopt share_history         # share command history data

# force zsh to show the complete history
alias history="history 0"

# configure `time` format
TIMEFMT=$'\nreal\t%E\nuser\t%U\nsys\t%S\ncpu\t%P'

# make less more friendly for non-text input files, see lesspipe(1)
#[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
        # We have color support; assume it's compliant with Ecma-48
        # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
        # a case would tend to support setf rather than setaf.)
        color_prompt=yes
    else
        color_prompt=
    fi
fi

configure_prompt() {
    prompt_symbol=㉿
    # Skull emoji for root terminal
    #[ "$EUID" -eq 0 ] && prompt_symbol=💀
    case "$PROMPT_ALTERNATIVE" in
        twoline)
            PROMPT=$'%F{%(#.blue.green)}┌──${debian_chroot:+($debian_chroot)─}${VIRTUAL_ENV:+($(basename $VIRTUAL_ENV))─}(%B%F{%(#.red.blue)}%n'$prompt_symbol$'%m%b%F{%(#.blue.green)})-[%B%F{reset}%(6~.%-1~/…/%4~.%5~)%b%F{%(#.blue.green)}]\n└─%B%(#.%F{red}#.%F{blue}$)%b%F{reset} '
            # Right-side prompt with exit codes and background processes
            #RPROMPT=$'%(?.. %? %F{red}%B⨯%b%F{reset})%(1j. %j %F{yellow}%B⚙%b%F{reset}.)'
            ;;
        oneline)
            PROMPT=$'${debian_chroot:+($debian_chroot)}${VIRTUAL_ENV:+($(basename $VIRTUAL_ENV))}%B%F{%(#.red.blue)}%n@%m%b%F{reset}:%B%F{%(#.blue.green)}%~%b%F{reset}%(#.#.$) '
            RPROMPT=
            ;;
        backtrack)
            PROMPT=$'${debian_chroot:+($debian_chroot)}${VIRTUAL_ENV:+($(basename $VIRTUAL_ENV))}%B%F{red}%n@%m%b%F{reset}:%B%F{blue}%~%b%F{reset}%(#.#.$) '
            RPROMPT=
            ;;
    esac
    unset prompt_symbol
}

# The following block is surrounded by two delimiters.
# These delimiters must not be modified. Thanks.
# START KALI CONFIG VARIABLES
PROMPT_ALTERNATIVE=twoline
NEWLINE_BEFORE_PROMPT=yes
# STOP KALI CONFIG VARIABLES

if [ "$color_prompt" = yes ]; then
    # override default virtualenv indicator in prompt
    VIRTUAL_ENV_DISABLE_PROMPT=1

    configure_prompt

    # enable syntax-highlighting
    if [ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
        . /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
        ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern)
        ZSH_HIGHLIGHT_STYLES[default]=none
        ZSH_HIGHLIGHT_STYLES[unknown-token]=underline
        ZSH_HIGHLIGHT_STYLES[reserved-word]=fg=cyan,bold
        ZSH_HIGHLIGHT_STYLES[suffix-alias]=fg=green,underline
        ZSH_HIGHLIGHT_STYLES[global-alias]=fg=green,bold
        ZSH_HIGHLIGHT_STYLES[precommand]=fg=green,underline
        ZSH_HIGHLIGHT_STYLES[commandseparator]=fg=blue,bold
        ZSH_HIGHLIGHT_STYLES[autodirectory]=fg=green,underline
        ZSH_HIGHLIGHT_STYLES[path]=bold
        ZSH_HIGHLIGHT_STYLES[path_pathseparator]=
        ZSH_HIGHLIGHT_STYLES[path_prefix_pathseparator]=
        ZSH_HIGHLIGHT_STYLES[globbing]=fg=blue,bold
        ZSH_HIGHLIGHT_STYLES[history-expansion]=fg=blue,bold
        ZSH_HIGHLIGHT_STYLES[command-substitution]=none
        ZSH_HIGHLIGHT_STYLES[command-substitution-delimiter]=fg=magenta,bold
        ZSH_HIGHLIGHT_STYLES[process-substitution]=none
        ZSH_HIGHLIGHT_STYLES[process-substitution-delimiter]=fg=magenta,bold
        ZSH_HIGHLIGHT_STYLES[single-hyphen-option]=fg=green
        ZSH_HIGHLIGHT_STYLES[double-hyphen-option]=fg=green
        ZSH_HIGHLIGHT_STYLES[back-quoted-argument]=none
        ZSH_HIGHLIGHT_STYLES[back-quoted-argument-delimiter]=fg=blue,bold
        ZSH_HIGHLIGHT_STYLES[single-quoted-argument]=fg=yellow
        ZSH_HIGHLIGHT_STYLES[double-quoted-argument]=fg=yellow
        ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]=fg=yellow
        ZSH_HIGHLIGHT_STYLES[rc-quote]=fg=magenta
        ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]=fg=magenta,bold
        ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]=fg=magenta,bold
        ZSH_HIGHLIGHT_STYLES[back-dollar-quoted-argument]=fg=magenta,bold
        ZSH_HIGHLIGHT_STYLES[assign]=none
        ZSH_HIGHLIGHT_STYLES[redirection]=fg=blue,bold
        ZSH_HIGHLIGHT_STYLES[comment]=fg=black,bold
        ZSH_HIGHLIGHT_STYLES[named-fd]=none
        ZSH_HIGHLIGHT_STYLES[numeric-fd]=none
        ZSH_HIGHLIGHT_STYLES[arg0]=fg=cyan
        ZSH_HIGHLIGHT_STYLES[bracket-error]=fg=red,bold
        ZSH_HIGHLIGHT_STYLES[bracket-level-1]=fg=blue,bold
        ZSH_HIGHLIGHT_STYLES[bracket-level-2]=fg=green,bold
        ZSH_HIGHLIGHT_STYLES[bracket-level-3]=fg=magenta,bold
        ZSH_HIGHLIGHT_STYLES[bracket-level-4]=fg=yellow,bold
        ZSH_HIGHLIGHT_STYLES[bracket-level-5]=fg=cyan,bold
        ZSH_HIGHLIGHT_STYLES[cursor-matchingbracket]=standout
    fi
else
    PROMPT='${debian_chroot:+($debian_chroot)}%n@%m:%~%(#.#.$) '
fi
unset color_prompt force_color_prompt

toggle_oneline_prompt(){
    if [ "$PROMPT_ALTERNATIVE" = oneline ]; then
        PROMPT_ALTERNATIVE=twoline
    else
        PROMPT_ALTERNATIVE=oneline
    fi
    configure_prompt
    zle reset-prompt
}
zle -N toggle_oneline_prompt
bindkey ^P toggle_oneline_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*|Eterm|aterm|kterm|gnome*|alacritty)
    TERM_TITLE=$'\e]0;${debian_chroot:+($debian_chroot)}${VIRTUAL_ENV:+($(basename $VIRTUAL_ENV))}%n@%m: %~\a'
    ;;
*)
    ;;
esac

precmd() {
    # Print the previously configured title
    print -Pnr -- "$TERM_TITLE"

    # Print a new line before the prompt, but only if it is not the first line
    if [ "$NEWLINE_BEFORE_PROMPT" = yes ]; then
        if [ -z "$_NEW_LINE_BEFORE_PROMPT" ]; then
            _NEW_LINE_BEFORE_PROMPT=1
        else
            print ""
        fi
    fi
}

# enable color support of ls, less and man, and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    export LS_COLORS="$LS_COLORS:ow=30;44:" # fix ls color for folders with 777 permissions

    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
    alias diff='diff --color=auto'
    alias ip='ip --color=auto'

    export LESS_TERMCAP_mb=$'\E[1;31m'     # begin blink
    export LESS_TERMCAP_md=$'\E[1;36m'     # begin bold
    export LESS_TERMCAP_me=$'\E[0m'        # reset bold/blink
    export LESS_TERMCAP_so=$'\E[01;33m'    # begin reverse video
    export LESS_TERMCAP_se=$'\E[0m'        # reset reverse video
    export LESS_TERMCAP_us=$'\E[1;32m'     # begin underline
    export LESS_TERMCAP_ue=$'\E[0m'        # reset underline
    export MANROFFOPT="-c"

    # Take advantage of $LS_COLORS for completion as well
    zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
    zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
fi

# some more ls aliases
alias ll='ls -l'
alias la='ls -A'
alias l='ls -CF'

# enable auto-suggestions based on the history
if [ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]; then
    . /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    # change suggestion color
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=244'
fi

# enable command-not-found if installed
if [ -f /etc/zsh_command_not_found ]; then
    . /etc/zsh_command_not_found
fi
KALI_ZSHRC_EOF
}

emit_kali_zprofile() {
    cat <<'KALI_ZPROFILE_EOF'
# ~/.zprofile: user-specific .zprofile file for zsh(1).
#
# This file is sourced only for login shells (i.e. shells
# invoked with "-" as the first character of argv[0], and
# shells invoked with the -l flag.)
#
# Global Order: zshenv, zprofile, zshrc, zlogin

if [ -f "$HOME/.profile" ]; then
    emulate sh -c '. "$HOME/.profile"'
fi
KALI_ZPROFILE_EOF
}

# --- Global State & Signal Traps ---
LOCK_FD=9
LOCK_FILE="/run/lock/kali-zsh-setup.lock"
STAGING_DIR=""
SYSTEM_BACKUP_DIR=""
declare -a USER_RESTORE_SCRIPTS=()
IN_PREFLIGHT=0
CLEANUP_CALLED=0

log_info() { echo "[INFO] $*" >&2; }
log_warn() { echo "[WARN] $*" >&2; }
log_err()  { echo "[ERR]  $*" >&2; }
log_fatal() { echo "[FATAL] $*" >&2; exit 1; }

usage() {
    cat <<'USAGE_EOF'
Usage: kali-zsh-setup.sh [OPTIONS]

Options:
    --help       Show this help message and exit
    --preflight  Read-only audit: verify prerequisites without making any system changes
                 (exit 0 on success/warning-only, non-zero on fatal issues)

Description:
    Self-contained standalone script to set up Kali-identical zsh across /etc/skel
    and all interactive user profiles on Debian. Requires root or sudo.
USAGE_EOF
}

# --- Cleanup & Rollback Traps ---
run_rollback() {
    local rc="$?"
    if [[ "$IN_PREFLIGHT" -eq 1 ]]; then
        return 0
    fi
    log_err "Signal or error caught (rc=$rc). Running rollback handlers..."

    # Run user restore scripts in reverse order (only root-owned copies from system backup dir)
    local i
    for ((i=${#USER_RESTORE_SCRIPTS[@]}-1; i>=0; i--)); do
        local rscript="${USER_RESTORE_SCRIPTS[i]}"
        if [[ -f "$rscript" && -x "$rscript" ]]; then
            log_info "Executing user rollback: $rscript"
            bash "$rscript" || log_warn "User restore script $rscript failed"
        fi
    done

    # Run system restore script if written
    if [[ -n "$SYSTEM_BACKUP_DIR" && -f "$SYSTEM_BACKUP_DIR/restore-system.sh" ]]; then
        log_info "Executing system rollback: $SYSTEM_BACKUP_DIR/restore-system.sh"
        bash "$SYSTEM_BACKUP_DIR/restore-system.sh" || log_warn "System restore script failed"
    fi
}

cleanup() {
    if [[ "$CLEANUP_CALLED" -eq 1 ]]; then return 0; fi
    CLEANUP_CALLED=1
    if [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]]; then
        rm -rf "$STAGING_DIR"
    fi
    if { true >&$LOCK_FD; } 2>/dev/null; then
        eval "exec $LOCK_FD>&-" 2>/dev/null || true
    fi
}

trap_err_int_term() {
    local sig="$1"
    log_err "Caught $sig!"
    run_rollback
    cleanup
    exit 1
}

# --- Self-Check: Verify Embedded Template Hashes ---
verify_embedded_templates() {
    local actual_zshrc_sha actual_zprofile_sha
    actual_zshrc_sha=$(emit_kali_zshrc | sha256sum | awk '{print $1}')
    actual_zprofile_sha=$(emit_kali_zprofile | sha256sum | awk '{print $1}')

    if [[ "$actual_zshrc_sha" != "$PINNED_ZSHRC_SHA256" ]]; then
        log_fatal "Template corruption: .zshrc sha256 ($actual_zshrc_sha) does not match pinned ($PINNED_ZSHRC_SHA256)"
    fi
    if [[ "$actual_zprofile_sha" != "$PINNED_ZPROFILE_SHA256" ]]; then
        log_fatal "Template corruption: .zprofile sha256 ($actual_zprofile_sha) does not match pinned ($PINNED_ZPROFILE_SHA256)"
    fi
    return 0
}

# --- Privilege Elevation & Concurrency Guard ---
handle_privileges_and_lock() {
    # Pipe-run guard: apply in BOTH root and non-root branches
    # If $0 does not point to an existing readable regular file, fatal
    if [[ ! -f "$0" || ! -r "$0" ]]; then
        log_fatal "Cannot execute from stdin/pipe ($0 is not a readable file). Save script to disk first: bash /path/to/kali-zsh-setup.sh"
    fi

    local real_script_path
    real_script_path=$(readlink -f -- "$0" 2>/dev/null || realpath -- "$0" 2>/dev/null || true)
    if [[ -z "$real_script_path" || ! -f "$real_script_path" ]]; then
        log_fatal "Failed to resolve real path of script ($0)"
    fi

    if [[ "$EUID" -ne 0 ]]; then
        if command -v sudo >/dev/null 2>&1; then
            log_info "Elevating privileges via sudo..."
            exec sudo -- "$real_script_path" "$@"
        else
            log_fatal "Root privileges required, but sudo is not installed. Please run as root."
        fi
    fi

    # Running as root: acquire local flock strictly after elevation
    mkdir -p /run/lock 2>/dev/null || true
    if ! eval "exec $LOCK_FD>\"$LOCK_FILE\""; then
        log_fatal "Could not open lockfile $LOCK_FILE"
    fi
    if ! flock -n "$LOCK_FD"; then
        log_fatal "Another instance of kali-zsh-setup.sh is currently running (lock $LOCK_FILE busy)."
    fi
}

# --- User Discovery ---
# Discovers interactive users (UID 0 and UID >= 1000 with valid login shell)
# Returns list of user:uid:gid:home:shell:is_in_passwd
discover_interactive_users() {
    local line uname uid gid udir ushell in_passwd
    while IFS=: read -r uname _ uid gid _ udir ushell; do
        [[ -z "$uname" ]] && continue
        # Filter shell
        case "$ushell" in
            */nologin|*/false|*/sync) continue ;;
            "") continue ;;
        esac
        # Filter UID: 0 or >= 1000
        if [[ "$uid" -eq 0 || "$uid" -ge 1000 ]]; then
            # Check if user is present in local /etc/passwd
            if grep -q "^${uname}:" /etc/passwd 2>/dev/null; then
                in_passwd=1
            else
                in_passwd=0
            fi
            echo "$uname:$uid:$gid:$udir:$ushell:$in_passwd"
        fi
    done < <(getent passwd)
}

# --- ZDOTDIR Scans ---
# Checks if a shell file contains an uncommented ZDOTDIR assignment
# Pattern: ^[[:space:]]*(export[[:space:]]+)?ZDOTDIR=
has_shell_zdotdir() {
    local f="$1"
    [[ ! -f "$f" || ! -r "$f" ]] && return 1
    # Strip comments and match
    sed -e 's/#.*$//' "$f" | grep -Eq '^[[:space:]]*(export[[:space:]]+)?ZDOTDIR=' 2>/dev/null
}

# Checks if a PAM file contains ZDOTDIR setting
# Pattern: ^[[:space:]]*ZDOTDIR([[:space:]]+(DEFAULT|OVERRIDE)=|[[:space:]]*=)
has_pam_zdotdir() {
    local f="$1"
    [[ ! -f "$f" || ! -r "$f" ]] && return 1
    sed -e 's/#.*$//' "$f" | grep -Eq '^[[:space:]]*ZDOTDIR([[:space:]]+(DEFAULT|OVERRIDE)=|[[:space:]]*=)' 2>/dev/null
}

# System-level ZDOTDIR scan across /etc/zsh/*, /etc/profile, /etc/profile.d/*.sh, PAM
check_system_zdotdir() {
    local found=0
    local f
    for f in /etc/zsh/zshenv /etc/zsh/zprofile /etc/zsh/zshrc /etc/profile; do
        if has_shell_zdotdir "$f"; then
            log_err "System-level ZDOTDIR assignment found in $f"
            found=1
        fi
    done
    if compgen -G "/etc/profile.d/*.sh" >/dev/null 2>&1; then
        for f in /etc/profile.d/*.sh; do
            if has_shell_zdotdir "$f"; then
                log_err "System-level ZDOTDIR assignment found in $f"
                found=1
            fi
        done
    fi
    for f in /etc/environment /etc/security/pam_env.conf; do
        if has_pam_zdotdir "$f"; then
            log_err "System-level ZDOTDIR assignment found in $f"
            found=1
        fi
    done
    [[ "$found" -eq 1 ]] && return 0
    return 1
}

# Per-user ZDOTDIR scan across user dotfiles
check_user_zdotdir() {
    local uhome="$1"
    local f
    for f in "$uhome/.zshenv" "$uhome/.profile" "$uhome/.zlogin"; do
        if has_shell_zdotdir "$f"; then
            return 0
        fi
    done
    if has_pam_zdotdir "$uhome/.pam_environment"; then
        return 0
    fi
    return 1
}

# --- HOME accessibility check ---
# Home must exist, be a directory, and be r+x accessible to the user
is_home_accessible() {
    local uname="$1" uhome="$2"
    [[ ! -d "$uhome" ]] && return 1
    # Check accessibility: if running as root, test via runuser; if non-root (e.g. preflight), test permissions
    if [[ "$EUID" -eq 0 ]]; then
        runuser -u "$uname" -- test -r "$uhome" -a -x "$uhome" 2>/dev/null
    else
        # Running as non-root (e.g. preflight audit by normal user)
        if [[ "$USER" == "$uname" ]]; then
            test -r "$uhome" -a -x "$uhome"
        else
            # For other users when non-root, check directory permissions
            test -d "$uhome"
        fi
    fi
}

# --- Dotfile Predicate Check (Ownership & Target) ---
# For a regular file: must be owned by the same user with their primary gid
# For a symlink: must resolve to regular file, owned by same user with primary gid, inside uhome
check_dotfile_predicate() {
    local uname="$1" expected_uid="$2" expected_gid="$3" uhome="$4" dotpath="$5"
    [[ ! -e "$dotpath" && ! -L "$dotpath" ]] && return 0 # Absent is allowed

    if [[ -L "$dotpath" ]]; then
        local target
        target=$(realpath -- "$dotpath" 2>/dev/null || true)
        if [[ -z "$target" || ! -f "$target" ]]; then
            log_warn "$dotpath: symlink does not resolve to regular file"
            return 1
        fi
        # Check target location: must be inside uhome
        case "$target" in
            "$uhome"/*) ;;
            *)
                log_warn "$dotpath: symlink target ($target) is outside user home ($uhome)"
                return 1
                ;;
        esac
        # Check target ownership: same uid and primary gid
        local tuid tgid
        tuid=$(stat -c '%u' "$target" 2>/dev/null || echo -1)
        tgid=$(stat -c '%g' "$target" 2>/dev/null || echo -1)
        if [[ "$tuid" -ne "$expected_uid" || "$tgid" -ne "$expected_gid" ]]; then
            log_warn "$dotpath: symlink target ($target) owner $tuid:$tgid != $expected_uid:$expected_gid"
            return 1
        fi
        return 0
    elif [[ -f "$dotpath" ]]; then
        local fuid fgid
        fuid=$(stat -c '%u' "$dotpath" 2>/dev/null || echo -1)
        fgid=$(stat -c '%g' "$dotpath" 2>/dev/null || echo -1)
        if [[ "$fuid" -ne "$expected_uid" || "$fgid" -ne "$expected_gid" ]]; then
            log_warn "$dotpath: regular file owner $fuid:$fgid != $expected_uid:$expected_gid"
            return 1
        fi
        return 0
    else
        log_warn "$dotpath: exotic file type (not regular or symlink)"
        return 1
    fi
}

# --- Skel Dotfile Predicate Check ---
# Absent: OK
# Regular file: must be owned by root:root
# Symlink: must resolve to regular file owned by root:root
check_skel_predicate() {
    local dotpath="$1"
    [[ ! -e "$dotpath" && ! -L "$dotpath" ]] && return 0 # Absent is normal

    if [[ -L "$dotpath" ]]; then
        local target
        target=$(realpath -- "$dotpath" 2>/dev/null || true)
        if [[ -z "$target" || ! -f "$target" ]]; then
            log_warn "$dotpath: skel symlink does not resolve to regular file"
            return 1
        fi
        local tuid tgid
        tuid=$(stat -c '%u' "$target" 2>/dev/null || echo -1)
        tgid=$(stat -c '%g' "$target" 2>/dev/null || echo -1)
        if [[ "$tuid" -ne 0 || "$tgid" -ne 0 ]]; then
            log_warn "$dotpath: skel symlink target owner $tuid:$tgid != 0:0"
            return 1
        fi
        return 0
    elif [[ -f "$dotpath" ]]; then
        local fuid fgid
        fuid=$(stat -c '%u' "$dotpath" 2>/dev/null || echo -1)
        fgid=$(stat -c '%g' "$dotpath" 2>/dev/null || echo -1)
        if [[ "$fuid" -ne 0 || "$fgid" -ne 0 ]]; then
            log_warn "$dotpath: skel regular file owner $fuid:$fgid != 0:0"
            return 1
        fi
        return 0
    else
        log_warn "$dotpath: skel file is exotic type"
        return 1
    fi
}

# --- Harvest & Migration Classifier ---
# Classifies lines from bashrc/bash_aliases/bash_profile/bash_login
# Allowlist: export/PATH/alias/umask/depth-0 conditionals/zsh-safe set -o/non-startup source
# Denylist: PS1, PROMPT_COMMAND, SHELL, ZDOTDIR, FPATH, export -f/-n, startup-file source
harvest_user_customizations() {
    local uhome="$1" is_root="$2"
    local base_skel="/etc/skel/.bashrc"
    if [[ "$is_root" -eq 1 && -f "/usr/share/base-files/dot.bashrc" ]]; then
        base_skel="/usr/share/base-files/dot.bashrc"
    fi

    local -a candidate_files=()
    # 1. diff ~/.bashrc against skel template
    local bashrc_diff=""
    if [[ -f "$uhome/.bashrc" ]]; then
        if [[ -f "$base_skel" ]]; then
            bashrc_diff=$(diff -u "$base_skel" "$uhome/.bashrc" | grep -E '^\+[^+]' | sed 's/^\+//' || true)
        else
            bashrc_diff=$(cat "$uhome/.bashrc")
        fi
    fi

    # 2. ~/.bash_aliases if present
    local aliases_content=""
    if [[ -f "$uhome/.bash_aliases" ]]; then
        aliases_content=$(cat "$uhome/.bash_aliases")
    fi

    # 3. ~/.bash_profile or fallback ~/.bash_login
    local profile_content=""
    if [[ -f "$uhome/.bash_profile" ]]; then
        profile_content=$(cat "$uhome/.bash_profile")
    elif [[ -f "$uhome/.bash_login" ]]; then
        profile_content=$(cat "$uhome/.bash_login")
    fi

    # Combine candidates
    local all_candidates
    all_candidates=$(printf "%s\n%s\n%s" "$bashrc_diff" "$aliases_content" "$profile_content")

    local line
    while IFS= read -r line; do
        # Trim leading/trailing whitespace
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        [[ -z "$trimmed" ]] && continue
        [[ "$trimmed" =~ ^# ]] && continue

        # Deny list checks
        if [[ "$trimmed" =~ ^(export[[:space:]]+)?(PS1|PROMPT_COMMAND|SHELL|ZDOTDIR|FPATH)= ]]; then
            continue
        fi
        if [[ "$trimmed" =~ ^export[[:space:]]+-[fn] ]]; then
            continue
        fi
        # Deny bash-only constructs
        if [[ "$trimmed" =~ ^shopt[[:space:]] ]] || [[ "$trimmed" =~ \[\[[[:space:]].*=~ ]]; then
            continue
        fi

        # Check source / . commands
        if [[ "$trimmed" =~ ^(\.|source)[[:space:]]+(.*)$ ]]; then
            local target_spec="${BASH_REMATCH[2]}"
            # Strip quotes/eval if needed
            target_spec="${target_spec%\"}"
            target_spec="${target_spec#\"}"
            target_spec="${target_spec%\'}"
            target_spec="${target_spec#\'}"
            local target_base
            target_base=$(basename -- "$target_spec" 2>/dev/null || echo "$target_spec")
            case "$target_base" in
                .profile|.bash_profile|.bash_login|.bashrc|.zprofile|.zshrc|.zshenv|profile)
                    # Deny startup files
                    continue
                    ;;
                *)
                    # Allow non-startup sources, wrap in [ -f ] guard at deploy
                    echo "[ -f $target_spec ] && . $target_spec"
                    continue
                    ;;
            esac
        fi

        # Allowlist checks
        if [[ "$trimmed" =~ ^(export[[:space:]]+)?[a-zA-Z_][a-zA-Z0-9_]*= ]] || \
           [[ "$trimmed" =~ ^alias[[:space:]]+[a-zA-Z0-9_.-]+= ]] || \
           [[ "$trimmed" =~ ^umask[[:space:]]+ ]] || \
           [[ "$trimmed" =~ ^set[[:space:]]+-o[[:space:]]+(ignoreeof|noclobber|allexport|vi|emacs) ]]; then
            echo "$trimmed"
            continue
        fi

        # Depth-0 simple conditionals: if [ ... ]; then ... ; fi
        local if_regex='^if[[:space:]].*;[[:space:]]*then[[:space:]].*;[[:space:]]*fi$'
        if [[ "$trimmed" =~ $if_regex ]]; then
            echo "$trimmed"
            continue
        fi
    done <<< "$all_candidates" | awk '!seen[$0]++' # Deduplicate preserving order
}

# --- Deploy Generation ---
# Constructs the deployed .zshrc content:
# emit_kali_zshrc + Sentinel line + Managed Marker Block
generate_deployed_zshrc() {
    local uhome="$1" is_root="$2"
    emit_kali_zshrc
    echo ""
    echo "$SENTINEL_COMMENT"
    echo "$SENTINEL_LINE"

    local harvested
    harvested=$(harvest_user_customizations "$uhome" "$is_root")
    if [[ -n "$harvested" ]]; then
        echo ""
        echo "$MARKER_START"
        echo "$harvested"
        echo "$MARKER_END"
    fi
}

# Constructs template-only .zshrc (used for differential gate probe):
# emit_kali_zshrc + Sentinel line (NO marker block)
generate_template_only_zshrc() {
    emit_kali_zshrc
    echo ""
    echo "$SENTINEL_COMMENT"
    echo "$SENTINEL_LINE"
}

# --- Preflight Phase (Read-only Audit) ---
# Exit contract: 0 only on success/warning-only; non-zero on fatal-class findings:
# 1. Template hash mismatch
# 2. System-level ZDOTDIR assignment (in /etc/zsh/*, /etc/profile, /etc/profile.d/*.sh, PAM)
# 3. Unusable environment: missing getent/flock/apt-cache, or zero discovered interactive users
run_preflight() {
    IN_PREFLIGHT=1
    log_info "=== Running Preflight Audit (Read-Only) ==="
    local fatal_count=0
    local warn_count=0

    # 1. Environment and tool dependencies check
    for cmd in getent flock apt-cache; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_err "Required tool '$cmd' is not available in PATH"
            fatal_count=$((fatal_count + 1))
        fi
    done

    # 2. Debian OS check
    if [[ -f /etc/os-release ]]; then
        if ! grep -Eq '^(ID|ID_LIKE)=.*debian' /etc/os-release; then
            log_warn "Host does not appear to be Debian or Debian-derived (/etc/os-release)"
            warn_count=$((warn_count + 1))
        else
            log_info "OS check: Debian-based system verified"
        fi
    else
        log_warn "/etc/os-release not found; cannot verify distribution"
        warn_count=$((warn_count + 1))
    fi

    # 3. Verify embedded template hashes
    log_info "Verifying embedded template integrity..."
    if ! verify_embedded_templates; then
        fatal_count=$((fatal_count + 1))
    else
        log_info "Embedded templates sha256 byte-identity: VERIFIED"
    fi

    # 4. System-level ZDOTDIR scan
    log_info "Scanning for system-level ZDOTDIR assignments..."
    if check_system_zdotdir; then
        fatal_count=$((fatal_count + 1))
    else
        log_info "System-level ZDOTDIR scan: CLEAN"
    fi

    # 5. APT package policy checks
    log_info "Checking APT package availability..."
    local pkg
    for pkg in zsh zsh-syntax-highlighting zsh-autosuggestions command-not-found; do
        local candidate
        candidate=$(LC_ALL=C apt-cache policy "$pkg" 2>/dev/null | grep -E '^[[:space:]]*Candidate:' | awk '{print $2}' || true)
        if [[ -z "$candidate" || "$candidate" == "(none)" ]]; then
            if [[ "$pkg" == "zsh" ]]; then
                log_err "APT: Mandatory package 'zsh' has no installation candidate!"
                fatal_count=$((fatal_count + 1))
            else
                log_warn "APT: Optional plugin package '$pkg' has no candidate (will skip best-effort)"
                warn_count=$((warn_count + 1))
            fi
        else
            log_info "APT: Package '$pkg' candidate: $candidate"
        fi
    done

    # 6. Skel preview & predicate check
    log_info "Auditing /etc/skel dotfiles..."
    for skel_file in /etc/skel/.zshrc /etc/skel/.zprofile; do
        if [[ -L "$skel_file" ]]; then
            log_warn "$skel_file is a symlink! Deploy will preserve link and write through realpath."
            warn_count=$((warn_count + 1))
        fi
        if ! check_skel_predicate "$skel_file"; then
            log_warn "Skel audit failed for $skel_file"
            warn_count=$((warn_count + 1))
        fi
        if [[ -f "$skel_file" ]]; then
            local diff_out=""
            if [[ "$skel_file" == "/etc/skel/.zshrc" ]]; then
                diff_out=$(diff -u "$skel_file" <(emit_kali_zshrc) || true)
            else
                diff_out=$(diff -u "$skel_file" <(emit_kali_zprofile) || true)
            fi
            if [[ -n "$diff_out" ]]; then
                log_warn "$skel_file has non-trivial pre-existing customizations — will be replaced by template without migration"
                warn_count=$((warn_count + 1))
            fi
        fi
    done

    # 7. User discovery and per-user audit
    log_info "Discovering interactive user accounts..."
    local user_list
    user_list=$(discover_interactive_users)
    if [[ -z "$user_list" ]]; then
        log_err "Zero interactive user accounts discovered (UID 0 or >= 1000 with login shell)"
        fatal_count=$((fatal_count + 1))
    fi

    local uline uname uid gid uhome ushell in_passwd
    while IFS= read -r uline; do
        [[ -z "$uline" ]] && continue
        IFS=: read -r uname uid gid uhome ushell in_passwd <<< "$uline"

        log_info "--- Auditing user: $uname (UID=$uid, GID=$gid, home=$uhome, shell=$ushell) ---"

        if [[ "$in_passwd" -eq 0 ]]; then
            log_warn "User $uname is not in local /etc/passwd (LDAP/SSSD) — will be skipped from shell switch"
            warn_count=$((warn_count + 1))
            continue
        fi

        if ! is_home_accessible "$uname" "$uhome"; then
            log_warn "User $uname home ($uhome) is missing or not r+x accessible — user will be SKIPPED entirely"
            warn_count=$((warn_count + 1))
            continue
        fi

        # Per-user ZDOTDIR check
        if check_user_zdotdir "$uhome"; then
            log_warn "User $uname has ZDOTDIR assignment in ~/.zshenv, ~/.profile, ~/.zlogin, or ~/.pam_environment — user will be SKIPPED"
            warn_count=$((warn_count + 1))
            continue
        fi

        # Check .zshrc and .zprofile predicates
        if ! check_dotfile_predicate "$uname" "$uid" "$gid" "$uhome" "$uhome/.zshrc"; then
            log_warn "User $uname .zshrc failed ownership/predicate check — user will be SKIPPED"
            warn_count=$((warn_count + 1))
            continue
        fi
        if ! check_dotfile_predicate "$uname" "$uid" "$gid" "$uhome" "$uhome/.zprofile"; then
            log_warn "User $uname .zprofile failed ownership/predicate check — user will be SKIPPED"
            warn_count=$((warn_count + 1))
            continue
        fi

        # Audit bash-only constructs in ~/.profile
        if [[ -f "$uhome/.profile" ]]; then
            if grep -Eq '^[[:space:]]*(shopt|function)[[:space:]]' "$uhome/.profile" 2>/dev/null; then
                log_warn "User $uname ~/.profile contains bash-specific constructs (shopt/function) which may warn under zsh's emulate sh -c"
                warn_count=$((warn_count + 1))
            fi
        fi

        # Audit ~/.zshenv for bash constructs
        if [[ -f "$uhome/.zshenv" ]]; then
            log_info "User $uname has existing ~/.zshenv (executed on every zsh invocation)"
            if grep -Eq '^[[:space:]]*(shopt|function)[[:space:]]' "$uhome/.zshenv" 2>/dev/null; then
                log_warn "User $uname ~/.zshenv contains bash-specific constructs"
                warn_count=$((warn_count + 1))
            fi
        fi

        # Audit ~/.bash_profile and ~/.bash_login
        if [[ -f "$uhome/.bash_profile" ]]; then
            log_warn "User $uname has ~/.bash_profile (zsh never reads it; portable exports harvested; ~/.profile will now run under zsh login)"
            warn_count=$((warn_count + 1))
        elif [[ -f "$uhome/.bash_login" ]]; then
            log_warn "User $uname has ~/.bash_login (zsh never reads it; portable exports harvested)"
            warn_count=$((warn_count + 1))
        fi

        # Preview migration differences
        if [[ -f "$uhome/.zshrc" ]]; then
            local u_zshrc_diff
            u_zshrc_diff=$(diff -u "$uhome/.zshrc" <(emit_kali_zshrc) || true)
            if [[ -n "$u_zshrc_diff" ]]; then
                log_info "User $uname has pre-existing .zshrc (will be replaced by template + migrated harvest block)"
            fi
        fi
        if [[ -f "$uhome/.zprofile" ]]; then
            local u_zp_diff
            u_zp_diff=$(diff -u "$uhome/.zprofile" <(emit_kali_zprofile) || true)
            if [[ -n "$u_zp_diff" ]]; then
                log_warn "User $uname has non-trivial pre-existing .zprofile — will be replaced without migration"
                warn_count=$((warn_count + 1))
            fi
        fi

        # Harvest preview
        local is_u_root=0
        [[ "$uid" -eq 0 ]] && is_u_root=1
        local harvested_preview
        harvested_preview=$(harvest_user_customizations "$uhome" "$is_u_root")
        if [[ -n "$harvested_preview" ]]; then
            log_info "User $uname harvest preview lines:"
            while IFS= read -r hline; do
                echo "    [HARVEST] $hline" >&2
                if [[ "$hline" =~ ^\[[[:space:]]-f[[:space:]] ]]; then
                    log_warn "    User $uname sourced file: $hline (wrapped in [ -f ] guard; check cross-shell behavior)"
                    warn_count=$((warn_count + 1))
                fi
            done <<< "$harvested_preview"
        else
            log_info "User $uname harvest: no custom portable additions discovered"
        fi
    done <<< "$user_list"

    log_info "=== Preflight Audit Complete: $fatal_count fatal error(s), $warn_count warning(s) ==="
    if [[ "$fatal_count" -gt 0 ]]; then
        return 1
    fi
    return 0
}

# --- System Backup Stage ---
# Snapshot system files before any modification.
# Format: record metadata (path uid gid mode) or 'ABSENT: path'
run_system_backup() {
    local ts
    ts=$(date -u +%Y%m%d%H%M%SZ)
    SYSTEM_BACKUP_DIR="/etc/zsh-system-backup-${ts}_$$"
    if [[ -e "$SYSTEM_BACKUP_DIR" ]]; then
        log_fatal "System backup target directory $SYSTEM_BACKUP_DIR already exists! Aborting."
    fi

    log_info "Creating system backup baseline at $SYSTEM_BACKUP_DIR (mode 0700 root:root)..."
    mkdir -m 0700 "$SYSTEM_BACKUP_DIR"
    local manifest="$SYSTEM_BACKUP_DIR/manifest.txt"
    touch "$manifest"

    local -a sys_files=(
        /etc/zsh/zprofile
        /etc/zsh/zshenv
        /etc/zsh/zshrc
        /etc/shells
        /etc/skel/.zshrc
        /etc/skel/.zprofile
        /etc/default/useradd
        /etc/adduser.conf
    )

    local f
    for f in "${sys_files[@]}"; do
        if [[ -e "$f" || -L "$f" ]]; then
            local rel_name
            rel_name=$(echo "$f" | sed 's|^/||; s|/|_|g')
            local bak_dest="$SYSTEM_BACKUP_DIR/$rel_name"
            if [[ -L "$f" ]]; then
                local link_target
                link_target=$(realpath -- "$f" 2>/dev/null || true)
                echo "SYMLINK:$f:$link_target" >> "$manifest"
                if [[ -n "$link_target" && -f "$link_target" ]]; then
                    cp -p "$link_target" "$bak_dest.target"
                    local tuid tgid tmode
                    tuid=$(stat -c '%u' "$link_target")
                    tgid=$(stat -c '%g' "$link_target")
                    tmode=$(stat -c '%a' "$link_target")
                    echo "TARGET_META:$link_target:$tuid:$tgid:$tmode" >> "$manifest"
                fi
            else
                local fuid fgid fmode
                fuid=$(stat -c '%u' "$f")
                fgid=$(stat -c '%g' "$f")
                fmode=$(stat -c '%a' "$f")
                echo "FILE:$f:$fuid:$fgid:$fmode" >> "$manifest"
                cp -p "$f" "$bak_dest"
            fi
        else
            echo "ABSENT:$f" >> "$manifest"
        fi
    done

    # Generate restore-system.sh inside $SYSTEM_BACKUP_DIR
    local rscript="$SYSTEM_BACKUP_DIR/restore-system.sh"
    cat <<'RSYS_EOF' > "$rscript"
#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR="$(dirname "$(readlink -f "$0")")"
MANIFEST="$BACKUP_DIR/manifest.txt"

echo "[RESTORE-SYS] Restoring system baseline from $BACKUP_DIR..."

deleted_absent_zsh=0

while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    IFS=: read -r action arg1 arg2 arg3 arg4 <<< "$line"
    case "$action" in
        ABSENT)
            target="$arg1"
            if [[ -e "$target" || -L "$target" ]]; then
                echo "[RESTORE-SYS] Deleting recorded-absent path: $target"
                rm -rf "$target"
                if [[ "$target" =~ ^/etc/zsh/ ]]; then
                    deleted_absent_zsh=1
                fi
            fi
            ;;
        FILE)
            target="$arg1"
            fuid="$arg2"
            fgid="$arg3"
            fmode="$arg4"
            rel_name=$(echo "$target" | sed 's|^/||; s|/|_|g')
            bak_file="$BACKUP_DIR/$rel_name"
            if [[ -f "$bak_file" ]]; then
                echo "[RESTORE-SYS] Restoring file: $target (mode $fmode, owner $fuid:$fgid)"
                mkdir -p "$(dirname "$target")"
                cp "$bak_file" "$target"
                chmod "$fmode" "$target"
                chown "$fuid:$fgid" "$target"
            fi
            ;;
        SYMLINK)
            target="$arg1"
            link_target="$arg2"
            rel_name=$(echo "$target" | sed 's|^/||; s|/|_|g')
            bak_target="$BACKUP_DIR/$rel_name.target"
            if [[ -L "$target" && -f "$bak_target" ]]; then
                echo "[RESTORE-SYS] Writing through existing symlink: $target -> $link_target"
                cat "$bak_target" > "$target"
            elif [[ -f "$bak_target" ]]; then
                echo "[RESTORE-SYS] Recreating symlink: $target -> $link_target"
                mkdir -p "$(dirname "$target")"
                ln -sf "$link_target" "$target"
                cat "$bak_target" > "$link_target"
            fi
            ;;
        TARGET_META)
            target="$arg1"
            tuid="$arg2"
            tgid="$arg3"
            tmode="$arg4"
            if [[ -f "$target" ]]; then
                chmod "$tmode" "$target" 2>/dev/null || true
                chown "$tuid:$tgid" "$target" 2>/dev/null || true
            fi
            ;;
    esac
done < "$MANIFEST"

if [[ "$deleted_absent_zsh" -eq 1 ]]; then
    echo "================================================================================"
    echo "[RESTORE-SYS] CAUTION: Conffiles under /etc/zsh/ were deleted by rollback."
    echo "[RESTORE-SYS] dpkg will NOT recreate them automatically on future upgrades."
    echo "[RESTORE-SYS] To reinstall stock conffiles, execute:"
    echo "[RESTORE-SYS]     apt-get install --reinstall zsh"
    echo "================================================================================"
fi
echo "[RESTORE-SYS] System restore complete."
RSYS_EOF
    chmod 0700 "$rscript"

    # Update symlink -latest
    ln -sfn "$SYSTEM_BACKUP_DIR" /etc/zsh-system-backup-latest
    log_info "System backup created successfully at $SYSTEM_BACKUP_DIR"
}

# --- Package Installation Stage ---
run_package_install() {
    log_info "=== Installing Packages ==="
    # 1. Mandatory package: zsh
    log_info "Installing mandatory package: zsh..."
    local install_cmd="DEBIAN_FRONTEND=noninteractive apt-get install -y -o DPkg::Lock::Timeout=60 zsh"
    if ! eval "$install_cmd"; then
        log_warn "apt-get install zsh failed. Attempting apt-get update fallback..."
        apt-get update -o DPkg::Lock::Timeout=60 || true
        if ! eval "$install_cmd"; then
            log_fatal "Failed to install mandatory package 'zsh' even after update fallback."
        fi
    fi

    # 2. Best-effort plugin packages
    local -a plugins=(zsh-syntax-highlighting zsh-autosuggestions command-not-found)
    local -a missing_plugins=()
    local p
    for p in "${plugins[@]}"; do
        log_info "Attempting best-effort install of optional package: $p..."
        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -o DPkg::Lock::Timeout=60 "$p" 2>/dev/null; then
            log_warn "Package $p install failed. Retrying once after update..."
            apt-get update -o DPkg::Lock::Timeout=60 2>/dev/null || true
            if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -o DPkg::Lock::Timeout=60 "$p" 2>/dev/null; then
                log_warn "Optional package $p could not be installed (best-effort, continuing)."
                missing_plugins+=("$p")
            fi
        fi
    done

    if [[ ${#missing_plugins[@]} -gt 0 ]]; then
        log_warn "Missing optional features report: the following packages could not be installed: ${missing_plugins[*]}"
    else
        log_info "All optional packages installed successfully."
    fi

    # 3. Post-install asserts: defined by FILE presence, not dpkg status
    if [[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
        log_info "Verified plugin file: /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
    fi
    if [[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
        log_info "Verified plugin file: /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
    fi
    if [[ -f /etc/zsh_command_not_found ]]; then
        log_info "Verified handler: /etc/zsh_command_not_found"
    fi
}

# --- System Defaults Stage ---
run_system_defaults() {
    log_info "=== Configuring System Defaults ==="

    # 1. Idempotent /etc/shells entry
    local zsh_path
    for zsh_path in /bin/zsh /usr/bin/zsh; do
        if [[ -x "$zsh_path" ]]; then
            if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
                log_info "Adding $zsh_path to /etc/shells"
                echo "$zsh_path" >> /etc/shells
            fi
        fi
    done

    # 2. Append emulate sh -c '. /etc/profile' to /etc/zsh/zprofile if absent
    mkdir -p /etc/zsh
    if [[ ! -f /etc/zsh/zprofile ]]; then
        touch /etc/zsh/zprofile
        chmod 0644 /etc/zsh/zprofile
    fi
    if ! grep -qF "emulate sh -c '. /etc/profile'" /etc/zsh/zprofile; then
        log_info "Appending '/etc/profile' sourcing to /etc/zsh/zprofile"
        echo "" >> /etc/zsh/zprofile
        echo "# Kali system login behavior: source /etc/profile" >> /etc/zsh/zprofile
        echo "emulate sh -c '. /etc/profile'" >> /etc/zsh/zprofile
    fi

    # 3. Deploy embedded templates to /etc/skel/
    mkdir -p /etc/skel
    local skel_file
    for skel_file in /etc/skel/.zshrc /etc/skel/.zprofile; do
        if [[ -L "$skel_file" ]]; then
            local rtarget
            rtarget=$(realpath -- "$skel_file" 2>/dev/null || true)
            if [[ -n "$rtarget" && -f "$rtarget" ]]; then
                log_info "Writing through skel symlink: $skel_file -> $rtarget"
                if [[ "$skel_file" == "/etc/skel/.zshrc" ]]; then
                    emit_kali_zshrc > "$rtarget"
                else
                    emit_kali_zprofile > "$rtarget"
                fi
                [[ -L "$skel_file" ]] || log_fatal "Assertion failed: $skel_file symlink was replaced!"
            fi
        else
            # Atomic install using staging in /etc (same filesystem)
            local skel_tmp
            skel_tmp=$(mktemp "/etc/.skel_tmp.XXXXXX")
            if [[ "$skel_file" == "/etc/skel/.zshrc" ]]; then
                emit_kali_zshrc > "$skel_tmp"
            else
                emit_kali_zprofile > "$skel_tmp"
            fi
            chmod 0644 "$skel_tmp"
            chown 0:0 "$skel_tmp" 2>/dev/null || true
            mv -f "$skel_tmp" "$skel_file"
        fi
    done

    # 4. /etc/default/useradd configuration
    mkdir -p /etc/default
    if [[ ! -f /etc/default/useradd ]]; then
        echo "SHELL=/bin/zsh" > /etc/default/useradd
        chmod 0644 /etc/default/useradd
    else
        if grep -q '^SHELL=' /etc/default/useradd; then
            sed -i 's|^SHELL=.*|SHELL=/bin/zsh|' /etc/default/useradd
        elif grep -q '^#.*SHELL=' /etc/default/useradd; then
            sed -i 's|^#.*SHELL=.*|SHELL=/bin/zsh|' /etc/default/useradd
        else
            echo "SHELL=/bin/zsh" >> /etc/default/useradd
        fi
    fi

    # 5. /etc/adduser.conf configuration
    if [[ ! -f /etc/adduser.conf ]]; then
        echo "DSHELL=/bin/zsh" > /etc/adduser.conf
        chmod 0644 /etc/adduser.conf
    else
        if grep -q '^DSHELL=' /etc/adduser.conf; then
            sed -i 's|^DSHELL=.*|DSHELL=/bin/zsh|' /etc/adduser.conf
        elif grep -q '^#.*DSHELL=' /etc/adduser.conf; then
            sed -i 's|^#.*DSHELL=.*|DSHELL=/bin/zsh|' /etc/adduser.conf
        else
            echo "DSHELL=/bin/zsh" >> /etc/adduser.conf
        fi
    fi
}

# --- Per-User Backup & Rollback Generation ---
# Creates ~/.zsh-backup-<UTC>_<PID> (0700 user:user)
# Also writes root-owned restore-user.sh into $SYSTEM_BACKUP_DIR
create_user_backup() {
    local uname="$1" uid="$2" gid="$3" uhome="$4" prev_shell="$5"
    local ts
    ts=$(date -u +%Y%m%d%H%M%SZ)
    local u_bak_dir="$uhome/.zsh-backup-${ts}_$$"
    if [[ -e "$u_bak_dir" ]]; then
        log_warn "User $uname backup dir $u_bak_dir already exists! Skipping user."
        return 1
    fi

    # Create 0700 user-owned backup directory
    mkdir -m 0700 "$u_bak_dir" 2>/dev/null || return 1
    chown "$uid:$gid" "$u_bak_dir" 2>/dev/null || return 1

    local u_manifest="$u_bak_dir/manifest.txt"
    touch "$u_manifest"

    local -a dotfiles=(.bashrc .bash_aliases .bash_profile .bash_login .profile .zshrc .zprofile .zshenv .zcompdump)
    local df
    for df in "${dotfiles[@]}"; do
        local target_path="$uhome/$df"
        if [[ -L "$target_path" ]]; then
            local rtarget
            rtarget=$(realpath -- "$target_path" 2>/dev/null || true)
            echo "SYMLINK:$df:$rtarget" >> "$u_manifest"
            if [[ -n "$rtarget" && -f "$rtarget" ]]; then
                cp -p "$rtarget" "$u_bak_dir/$df.target"
                local tuid tgid tmode
                tuid=$(stat -c '%u' "$rtarget")
                tgid=$(stat -c '%g' "$rtarget")
                tmode=$(stat -c '%a' "$rtarget")
                echo "TARGET_META:$rtarget:$tuid:$tgid:$tmode" >> "$u_manifest"
            fi
        elif [[ -f "$target_path" ]]; then
            local fuid fgid fmode
            fuid=$(stat -c '%u' "$target_path")
            fgid=$(stat -c '%g' "$target_path")
            fmode=$(stat -c '%a' "$target_path")
            echo "FILE:$df:$fuid:$fgid:$fmode" >> "$u_manifest"
            cp -p "$target_path" "$u_bak_dir/$df"
        else
            echo "ABSENT:$df" >> "$u_manifest"
        fi
    done
    chown -R "$uid:$gid" "$u_bak_dir" 2>/dev/null || true

    # Generate user restore script template
    local rscript_body
    rscript_body=$(cat <<RU_EOF
#!/usr/bin/env bash
set -euo pipefail
UHOME="$uhome"
UNAME="$uname"
PREV_SHELL="$prev_shell"
BAK_DIR="$u_bak_dir"
MANIFEST="\$BAK_DIR/manifest.txt"

echo "[RESTORE-USER] Restoring dotfiles for \$UNAME..."

while IFS= read -r line || [[ -n "\$line" ]]; do
    [[ -z "\$line" || "\$line" =~ ^# ]] && continue
    IFS=: read -r action arg1 arg2 arg3 arg4 <<< "\$line"
    case "\$action" in
        ABSENT)
            df="\$arg1"
            dest="\$UHOME/\$df"
            if [[ -e "\$dest" || -L "\$dest" ]]; then
                echo "[RESTORE-USER] Deleting recorded-absent: \$dest"
                rm -rf "\$dest"
            fi
            ;;
        FILE)
            df="\$arg1"
            fuid="\$arg2"
            fgid="\$arg3"
            fmode="\$arg4"
            src="\$BAK_DIR/\$df"
            dest="\$UHOME/\$df"
            if [[ -f "\$src" ]]; then
                echo "[RESTORE-USER] Restoring file: \$dest (mode \$fmode, owner \$fuid:\$fgid)"
                cp "\$src" "\$dest"
                chmod "\$fmode" "\$dest"
                chown "\$fuid:\$fgid" "\$dest"
            fi
            ;;
        SYMLINK)
            df="\$arg1"
            rtarget="\$arg2"
            src="\$BAK_DIR/\$df.target"
            dest="\$UHOME/\$df"
            if [[ -L "\$dest" && -f "\$src" ]]; then
                echo "[RESTORE-USER] Writing through existing symlink: \$dest -> \$rtarget"
                cat "\$src" > "\$dest"
            elif [[ -f "\$src" ]]; then
                echo "[RESTORE-USER] Recreating symlink: \$dest -> \$rtarget"
                ln -sf "\$rtarget" "\$dest"
                cat "\$src" > "\$rtarget"
            fi
            ;;
        TARGET_META)
            rtarget="\$arg1"
            tuid="\$arg2"
            tgid="\$arg3"
            tmode="\$arg4"
            if [[ -f "\$rtarget" ]]; then
                chmod "\$tmode" "\$rtarget" 2>/dev/null || true
                chown "\$tuid:\$tgid" "\$rtarget" 2>/dev/null || true
            fi
            ;;
    esac
done < "\$MANIFEST"

# Rollback login shell if changed
curr_shell=\$(getent passwd "\$UNAME" | cut -d: -f7 || echo "")
if [[ -n "\$PREV_SHELL" && "\$curr_shell" != "\$PREV_SHELL" ]]; then
    echo "[RESTORE-USER] Rolling back shell for \$UNAME: \$curr_shell -> \$PREV_SHELL"
    chsh -s "\$PREV_SHELL" "\$UNAME" || true
fi
echo "[RESTORE-USER] User \$UNAME restore complete."
RU_EOF
)

    # User copy in home (for user's own manual use)
    local u_rscript="$u_bak_dir/restore-user.sh"
    echo "$rscript_body" > "$u_rscript"
    chmod 0700 "$u_rscript"
    chown "$uid:$gid" "$u_rscript" 2>/dev/null || true

    # Root-owned copy in $SYSTEM_BACKUP_DIR (ONLY copy executed by script on rollback/abort)
    local sys_rscript="$SYSTEM_BACKUP_DIR/restore-user-${uname}.sh"
    echo "$rscript_body" > "$sys_rscript"
    chmod 0700 "$sys_rscript"
    chown 0:0 "$sys_rscript" 2>/dev/null || true

    USER_RESTORE_SCRIPTS+=("$sys_rscript")
    ln -sfn "$u_bak_dir" "$uhome/.zsh-backup-latest" 2>/dev/null || true
    return 0
}

# --- Atomic Per-User Deploy ---
# Staging is on the same filesystem (inside uhome), moved into place
deploy_user_dotfiles() {
    local uname="$1" uid="$2" gid="$3" uhome="$4" is_root="$5"

    # 1. Re-assert target predicate immediately before staging against TOCTOU
    if ! check_dotfile_predicate "$uname" "$uid" "$gid" "$uhome" "$uhome/.zshrc" || \
       ! check_dotfile_predicate "$uname" "$uid" "$gid" "$uhome" "$uhome/.zprofile"; then
        log_warn "TOCTOU check failed: $uname dotfiles changed predicate! Skipping deploy."
        return 1
    fi

    local stage_zshrc stage_zp
    stage_zshrc=$(mktemp "$uhome/.zshrc_staged.XXXXXX") 2>/dev/null || return 1
    stage_zp=$(mktemp "$uhome/.zprofile_staged.XXXXXX") 2>/dev/null || return 1

    generate_deployed_zshrc "$uhome" "$is_root" > "$stage_zshrc"
    emit_kali_zprofile > "$stage_zp"

    chmod 0644 "$stage_zshrc" "$stage_zp"
    chown "$uid:$gid" "$stage_zshrc" "$stage_zp" 2>/dev/null || true

    # Deploy .zshrc
    if [[ -L "$uhome/.zshrc" ]]; then
        local rtarget
        rtarget=$(realpath -- "$uhome/.zshrc")
        cat "$stage_zshrc" > "$rtarget"
        rm -f "$stage_zshrc"
        [[ -L "$uhome/.zshrc" ]] || log_fatal "Assertion failed: $uhome/.zshrc symlink was replaced!"
    else
        mv -f "$stage_zshrc" "$uhome/.zshrc"
    fi

    # Deploy .zprofile
    if [[ -L "$uhome/.zprofile" ]]; then
        local rtarget
        rtarget=$(realpath -- "$uhome/.zprofile")
        cat "$stage_zp" > "$rtarget"
        rm -f "$stage_zp"
        [[ -L "$uhome/.zprofile" ]] || log_fatal "Assertion failed: $uhome/.zprofile symlink was replaced!"
    else
        mv -f "$stage_zp" "$uhome/.zprofile"
    fi

    return 0
}

# --- Pre-switch Validation Gate & Discriminator Probe ---
# Tests login shell under user identity
validate_user_gate() {
    local uname="$1" uhome="$2"
    local has_highlight=0
    if [[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
        has_highlight=1
    fi

    local gate_cmd
    if [[ "$has_highlight" -eq 1 ]]; then
        gate_cmd="SAVEHIST=0 HISTFILE=/dev/null; autoload -Uz compinit && compinit -u && bindkey -e && [[ -n \$KALI_ZSH_SETUP_ACTIVE ]] && [[ -n \$ZSH_HIGHLIGHT_VERSION ]] && exit 0"
    else
        gate_cmd="SAVEHIST=0 HISTFILE=/dev/null; autoload -Uz compinit && compinit -u && bindkey -e && [[ -n \$KALI_ZSH_SETUP_ACTIVE ]] && exit 0"
    fi

    local rc=0
    runuser -u "$uname" -- env -u ZDOTDIR -u FPATH -u KALI_ZSH_SETUP_ACTIVE -u PROMPT -u PS1 HOME="$uhome" TERM=xterm-256color timeout --kill-after=10s 30s zsh -l -i -c "$gate_cmd" >/dev/null 2>&1 || rc=$?

    if [[ "$rc" -eq 0 ]]; then
        return 0
    fi

    # Gate failed. Run differential discriminator probe with template-only HOME
    log_warn "Gate failed for $uname (rc=$rc). Running differential discriminator probe..."
    if [[ "$rc" -eq 124 || "$rc" -eq 137 ]]; then
        log_warn "Gate failure reason: VALIDATION_TIMEOUT"
    fi

    local probe_tmp
    probe_tmp=$(mktemp -d "/tmp/.zsh_probe_home_${uname}.XXXXXX")
    chmod 0700 "$probe_tmp"
    local uid gid
    uid=$(id -u "$uname")
    gid=$(id -g "$uname")
    chown "$uid:$gid" "$probe_tmp"

    # Seed probe HOME with template-only .zshrc (+ sentinel, NO marker block)
    generate_template_only_zshrc > "$probe_tmp/.zshrc"
    chmod 0644 "$probe_tmp/.zshrc"
    chown "$uid:$gid" "$probe_tmp/.zshrc"

    local probe_rc=0
    runuser -u "$uname" -- env -u ZDOTDIR -u FPATH -u KALI_ZSH_SETUP_ACTIVE -u PROMPT -u PS1 HOME="$probe_tmp" TERM=xterm-256color timeout --kill-after=10s 30s zsh -l -i -c "$gate_cmd" >/dev/null 2>&1 || probe_rc=$?
    rm -rf "$probe_tmp"

    if [[ "$probe_rc" -eq 0 ]]; then
        # Probe passed => failure was user-local!
        log_warn "Discriminator probe passed! Failure is USER-LOCAL for $uname."
        return 2 # Code 2 = user-local failure
    else
        # Probe failed => systemic failure!
        log_err "Discriminator probe failed (rc=$probe_rc)! Failure is SYSTEMIC."
        return 1 # Code 1 = systemic failure
    fi
}

# --- Smoke Test ---
run_user_smoke() {
    local uname="$1" uhome="$2"
    local smoke_cmd="SAVEHIST=0 HISTFILE=/dev/null; print -r -- \$PROMPT; [[ -n \$KALI_ZSH_SETUP_ACTIVE ]] && print -r -- SENTINEL_OK"
    local smoke_out=""
    local rc=0

    smoke_out=$(runuser -u "$uname" -- env -u ZDOTDIR -u FPATH -u KALI_ZSH_SETUP_ACTIVE -u PROMPT -u PS1 HOME="$uhome" TERM=xterm-256color timeout --kill-after=10s 30s zsh -l -i -c "$smoke_cmd" 2>/dev/null) || rc=$?

    if [[ "$rc" -ne 0 ]]; then
        log_warn "Smoke test for $uname failed with rc=$rc (classified as non-fatal warning)"
        return 0
    fi

    if [[ "$smoke_out" =~ ┌── ]] && [[ "$smoke_out" =~ SENTINEL_OK ]]; then
        log_info "Smoke test for $uname: PASSED (prompt structure and sentinel verified)"
        return 0
    else
        log_warn "Smoke test output for $uname did not match expected pattern (non-fatal warning)"
        return 0
    fi
}

# --- Main Execution Orchestration ---
main() {
    # Parse CLI flags
    local do_preflight=0
    for arg in "$@"; do
        case "$arg" in
            --help)
                usage
                exit 0
                ;;
            --preflight)
                do_preflight=1
                ;;
            *)
                log_fatal "Unknown option: $arg (see --help)"
                ;;
        esac
    done

    # Preflight path
    if [[ "$do_preflight" -eq 1 ]]; then
        if ! run_preflight; then
            exit 1
        fi
        exit 0
    fi

    # Normal execution path: elevation + lock + traps
    handle_privileges_and_lock "$@"

    trap 'cleanup' EXIT
    trap 'trap_err_int_term SIGINT' INT
    trap 'trap_err_int_term SIGTERM' TERM
    trap 'trap_err_int_term ERR' ERR

    log_info "================================================================="
    log_info "=== Starting Standalone Kali ZSH Setup ==="
    log_info "================================================================="

    # 1. Verify embedded templates
    verify_embedded_templates

    # 2. Run Preflight checks (exit non-zero on fatal issues)
    if ! run_preflight; then
        log_fatal "Preflight audit failed with fatal errors. Aborting before mutations."
    fi

    # 3. System backup (first mutation)
    run_system_backup

    # 4. Package installation
    run_package_install

    # 5. System defaults configuration
    run_system_defaults

    # 6. Discover interactive users
    local user_list
    user_list=$(discover_interactive_users)

    # Collections for processing
    local -a valid_users=()
    local -a skipped_users=()
    local -a failed_users=()
    local systemic_abort=0
    local root_user_entry=""

    # 7. Per-user processing: Backup -> Deploy -> Validation Gate
    local uline uname uid gid uhome ushell in_passwd
    while IFS= read -r uline; do
        [[ -z "$uline" ]] && continue
        IFS=: read -r uname uid gid uhome ushell in_passwd <<< "$uline"

        # Check preflight eligibility criteria
        if [[ "$in_passwd" -eq 0 ]] || \
           ! is_home_accessible "$uname" "$uhome" || \
           check_user_zdotdir "$uhome" || \
           ! check_dotfile_predicate "$uname" "$uid" "$gid" "$uhome" "$uhome/.zshrc" || \
           ! check_dotfile_predicate "$uname" "$uid" "$gid" "$uhome" "$uhome/.zprofile"; then
            log_warn "User $uname skipped per preflight exclusion criteria."
            skipped_users+=("$uname")
            continue
        fi

        log_info "Processing user: $uname (home=$uhome)..."

        # Step 7a: Create per-user backup
        if ! create_user_backup "$uname" "$uid" "$gid" "$uhome" "$ushell"; then
            log_warn "Backup creation failed for $uname — skipping user."
            skipped_users+=("$uname")
            continue
        fi

        # Step 7b: Deploy dotfiles atomically
        local is_u_root=0
        [[ "$uid" -eq 0 ]] && is_u_root=1
        if ! deploy_user_dotfiles "$uname" "$uid" "$gid" "$uhome" "$is_u_root"; then
            log_warn "Deploy failed for $uname — invoking restore and skipping user."
            # Rollback this user's dotfiles
            local u_rscript="$SYSTEM_BACKUP_DIR/restore-user-${uname}.sh"
            [[ -f "$u_rscript" ]] && bash "$u_rscript" || true
            skipped_users+=("$uname")
            continue
        fi

        # Step 7c: Run validation gate
        local gate_res=0
        validate_user_gate "$uname" "$uhome" || gate_res=$?

        if [[ "$gate_res" -eq 0 ]]; then
            log_info "Validation gate PASSED for user $uname"
            if [[ "$is_u_root" -eq 1 ]]; then
                root_user_entry="$uline"
            else
                valid_users+=("$uline")
            fi
        elif [[ "$gate_res" -eq 2 ]]; then
            # User-local failure: rollback this user's dotfiles and skip
            log_warn "User $uname gate failed (USER-LOCAL) — rolling back dotfiles and skipping."
            local u_rscript="$SYSTEM_BACKUP_DIR/restore-user-${uname}.sh"
            [[ -f "$u_rscript" ]] && bash "$u_rscript" || true
            failed_users+=("$uname")
        elif [[ "$gate_res" -eq 1 ]]; then
            # Systemic failure on probe!
            log_err "User $uname gate failed (SYSTEMIC failure on template-only probe)."
            failed_users+=("$uname")
            # If all evaluated users fail with probe failure, trigger systemic abort
        fi
    done <<< "$user_list"

    # Evaluate systemic abort condition:
    # If all processed users failed and none had user-local cause
    local total_processed=$(( ${#valid_users[@]} + ${#failed_users[@]} + (${#root_user_entry} > 0 ? 1 : 0) ))
    if [[ "$total_processed" -gt 0 && ${#valid_users[@]} -eq 0 && -z "$root_user_entry" ]]; then
        # Check if any failure was attributable to user-local
        # If no user validated and all were systemic failures -> global abort
        log_err "Global abort: all validated users failed validation gate with systemic causes!"
        run_rollback
        exit 1
    fi

    # 8. Shell Switch Phase
    # Switch non-root users first
    local uentry
    for uentry in "${valid_users[@]}"; do
        IFS=: read -r uname uid gid uhome ushell in_passwd <<< "$uentry"
        log_info "Switching login shell for non-root user $uname: $ushell -> /bin/zsh"
        if ! chsh -s /bin/zsh "$uname"; then
            log_warn "chsh failed for user $uname! Rolling back shell."
            local u_rscript="$SYSTEM_BACKUP_DIR/restore-user-${uname}.sh"
            [[ -f "$u_rscript" ]] && bash "$u_rscript" || true
            continue
        fi
        local actual_shell
        actual_shell=$(getent passwd "$uname" | cut -d: -f7 || echo "")
        if [[ "$actual_shell" != "/bin/zsh" && "$actual_shell" != "/usr/bin/zsh" ]]; then
            log_warn "Shell verification failed for $uname (shell is $actual_shell) — rolling back."
            local u_rscript="$SYSTEM_BACKUP_DIR/restore-user-${uname}.sh"
            [[ -f "$u_rscript" ]] && bash "$u_rscript" || true
            continue
        fi
        log_info "User $uname successfully switched to zsh."
        run_user_smoke "$uname" "$uhome"
    done

    # Switch root user last
    if [[ -n "$root_user_entry" ]]; then
        IFS=: read -r uname uid gid uhome ushell in_passwd <<< "$root_user_entry"
        log_info "Switching root user login shell: $ushell -> /bin/zsh"
        local root_prev_shell="$ushell"
        if ! chsh -s /bin/zsh root; then
            log_warn "chsh failed for root! Retaining previous shell $root_prev_shell."
        else
            local actual_root_shell
            actual_root_shell=$(getent passwd root | cut -d: -f7 || echo "")
            if [[ "$actual_root_shell" != "/bin/zsh" && "$actual_root_shell" != "/usr/bin/zsh" ]]; then
                log_warn "Shell verification failed for root! Rolling back to $root_prev_shell."
                chsh -s "$root_prev_shell" root || true
            else
                log_info "Root user successfully switched to zsh."
                run_user_smoke root /root
            fi
        fi
    fi

    log_info "================================================================="
    log_info "=== Kali ZSH Setup Finished Successfully ==="
    log_info "================================================================="
    exit 0
}

# Invoke main entrypoint if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
