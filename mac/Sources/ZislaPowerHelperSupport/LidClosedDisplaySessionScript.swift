public enum LidClosedDisplaySessionScript {
    // The privileged process owns the original setting. EOF restores it even if the app crashes.
    // sh -p ignores shell startup files; only fixed system executables run with elevated privileges.
    public static let script = #"""
    export PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C
    read_state() {
        settings=$(/usr/bin/pmset -g) || return 1
        printf '%s\n' "$settings" | /usr/bin/awk '
            /^System-wide power settings:$/ { header = 1; next }
            /^Currently in use:$/ { exit }
            header && $1 == "SleepDisabled" {
                if (seen++ || NF != 2 || $2 !~ /^[01]$/) { invalid = 1; exit }
                value = $2
            }
            END { if (!header || invalid) exit 1; print seen ? value : 0 }
        '
    }
    original=$(read_state) || exit 1
    changed=0
    restore() {
        [ "$changed" = 1 ] || return 0
        /usr/bin/pmset -a disablesleep "$original" >/dev/null
        current=$(read_state) || return 1
        [ "$current" = "$original" ] || return 1
        changed=0
    }
    trap 'restore' EXIT
    if [ "$original" = 0 ]; then
        changed=1
        /usr/bin/pmset -a disablesleep 1 >/dev/null || exit 1
    fi
    current=$(read_state) || exit 1
    [ "$current" = 1 ] || exit 1
    printf 'ready\n'
    while IFS= read -r request; do
        [ "$request" = stop ] || exit 1
        if restore; then
            printf 'restored\n'
            exit 0
        fi
        printf 'failed\n'
    done
    """#
}
