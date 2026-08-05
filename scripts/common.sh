#!/system/bin/sh

MODULE_DIR=${0%/*}
case "$MODULE_DIR" in
    */scripts) MODULE_DIR=${MODULE_DIR%/scripts} ;;
esac

SERVICE_SCRIPT="$MODULE_DIR/service.sh"

CONFIG_DIR="/storage/emulated/0/Documents/Oplus_Smart_Dimming"
INSTALL_SETTINGS_FILE="$MODULE_DIR/settings.prop"
DEBUG_LOG_FILE="$CONFIG_DIR/smart_dimming.log"
RUN_DIR="$MODULE_DIR/run"
PID_FILE="$RUN_DIR/service.pid"
GUARD_PID_FILE="$RUN_DIR/guard.pid"
LOGCAT_PID_FILE="$RUN_DIR/screen_logcat.pid"
REFRESH_EVENT_STAMP_FILE="$RUN_DIR/refresh_event.stamp"
STATE_FILE="$RUN_DIR/state"
BOOT_LOG_FILE="$RUN_DIR/boot.log"
SETTING_KEY="display_single_pulse_eyeprotection_switch"
DEBUG_LOG_ENABLED="0"
GUARD_MODE="poll"

wait_for_boot() {
    until [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ]; do
        sleep 1
    done

    until [ -d "/sdcard" ] || [ -d "/storage/emulated/0" ]; do
        sleep 2
    done

}

ensure_run_dir() {
    [ -d "$RUN_DIR" ] || mkdir -p "$RUN_DIR" 2>/dev/null || return 1
    chmod 0755 "$RUN_DIR" 2>/dev/null
}

log_boot() {
    [ "$DEBUG_LOG_ENABLED" = "1" ] || return 0
    ensure_run_dir || return 0
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$BOOT_LOG_FILE"
}

read_install_debug_logging() {
    value=$(sed -n 's/^[[:space:]]*debug_logging[[:space:]]*=[[:space:]]*//p' "$INSTALL_SETTINGS_FILE" 2>/dev/null | tail -n 1 | sed 's/[[:space:]]*$//')
    case "$value" in
        1|on|true|enabled) printf '%s\n' "1" ;;
        *) printf '%s\n' "0" ;;
    esac
}

service_alive() {
    [ -f "$PID_FILE" ] || return 1

    service_pid=$(cat "$PID_FILE" 2>/dev/null)
    [ -n "$service_pid" ] || return 1
    [ -d "/proc/$service_pid" ] || return 1

    cmdline=$(tr '\0' ' ' < "/proc/$service_pid/cmdline" 2>/dev/null)
    case "$cmdline" in
        *"$SERVICE_SCRIPT"*) return 0 ;;
        *) return 1 ;;
    esac
}

read_install_guard_mode() {
    mode=$(sed -n 's/^[[:space:]]*guard_mode[[:space:]]*=[[:space:]]*//p' "$INSTALL_SETTINGS_FILE" 2>/dev/null | tail -n 1 | sed 's/[[:space:]]*$//')
    case "$mode" in
        logcat|event|events) printf '%s\n' "logcat" ;;
        *) printf '%s\n' "poll" ;;
    esac
}

load_debug_config() {
    ensure_run_dir

    GUARD_MODE=$(read_install_guard_mode)
    case "$GUARD_MODE" in
        logcat|event|events) GUARD_MODE="logcat" ;;
        *) GUARD_MODE="poll" ;;
    esac

    DEBUG_LOG_ENABLED=$(read_install_debug_logging)
    case "$DEBUG_LOG_ENABLED" in
        1|on|true|enabled) DEBUG_LOG_ENABLED="1" ;;
        *) DEBUG_LOG_ENABLED="0" ;;
    esac
}

log_debug() {
    [ "$DEBUG_LOG_ENABLED" = "1" ] || return 0
    [ -d "$CONFIG_DIR" ] || mkdir -p "$CONFIG_DIR" 2>/dev/null || return 0
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$DEBUG_LOG_FILE"
}

read_current_state() {
    users=$(list_android_users)
    saw_default=0
    saw_reserved=0

    for user_id in $users; do
        current=$(read_setting_for_user "$user_id")
        case "$current" in
            0) printf '%s\n' "0"; return 0 ;;
            2) saw_default=1 ;;
            1) saw_reserved=1 ;;
        esac
    done

    [ "$saw_default" = "1" ] && { printf '%s\n' "2"; return 0; }
    [ "$saw_reserved" = "1" ] && { printf '%s\n' "1"; return 0; }
    printf '%s\n' "-1"
}

read_setting_for_user() {
    user_id="$1"

    for command_variant in settings_user cmd_settings_user; do
        case "$command_variant" in
            settings_user)
                value=$(/system/bin/settings --user "$user_id" get secure "$SETTING_KEY" 2>/dev/null)
                ;;
            cmd_settings_user)
                value=$(/system/bin/cmd settings get --user "$user_id" secure "$SETTING_KEY" 2>/dev/null)
                ;;
        esac

        case "$value" in
            0|1|2) printf '%s\n' "$value"; return 0 ;;
        esac
    done

    if [ "$user_id" = "0" ]; then
        for command_variant in settings_default cmd_settings_default; do
            case "$command_variant" in
                settings_default)
                    value=$(/system/bin/settings get secure "$SETTING_KEY" 2>/dev/null)
                    ;;
                cmd_settings_default)
                    value=$(/system/bin/cmd settings get secure "$SETTING_KEY" 2>/dev/null)
                    ;;
            esac

            case "$value" in
                0|1|2) printf '%s\n' "$value"; return 0 ;;
            esac
        done
    fi

    printf '%s\n' "-1"
}

list_android_users() {
    users=$(
        /system/bin/cmd user list 2>/dev/null \
            | sed -n 's/.*UserInfo{\([0-9][0-9]*\):.*/\1/p' \
            | sort -n -u
    )

    if [ -n "$users" ]; then
        printf '%s\n' "$users"
    else
        printf '%s\n' "0 999"
    fi
}

restore_default_state_all_users() {
    ok=1
    for user_id in $(list_android_users); do
        current=$(read_setting_for_user "$user_id")
        case "$current" in
            0|1|2)
                restore_default_state_for_user "$user_id" || ok=0
                ;;
        esac
    done
    [ "$ok" = "1" ]
}

restore_default_state_for_user() {
    user_id="$1"

    /system/bin/settings --user "$user_id" put secure "$SETTING_KEY" 2 >/dev/null 2>&1 && return 0
    /system/bin/cmd settings put --user "$user_id" secure "$SETTING_KEY" 2 >/dev/null 2>&1 && return 0

    if [ "$user_id" = "0" ]; then
        /system/bin/settings put secure "$SETTING_KEY" 2 >/dev/null 2>&1 && return 0
        /system/bin/cmd settings put secure "$SETTING_KEY" 2 >/dev/null 2>&1 && return 0
    fi

    return 1
}

read_dpms() {
    cat /sys/class/drm/card0-DSI-1/dpms 2>/dev/null || printf 'unknown\n'
}

read_refresh_rate() {
    display_rate=$(
        /system/bin/dumpsys display 2>/dev/null \
            | grep -m 1 'DisplayDeviceInfo' \
            | sed -n 's/.*renderFrameRate \([0-9][0-9.]*\).*/\1/p'
    )
    case "$display_rate" in
        ''|*[!0-9.]*|0|0.0|0.00) ;;
        *) printf '%s\n' "$display_rate"; return 0 ;;
    esac

    for node in /sys/class/drm/card0-sde-crtc-*/measured_fps; do
        [ -f "$node" ] || continue
        value=$(cat "$node" 2>/dev/null)
        case "$value" in
            ''|*[!0-9.]*|0|0.0|0.00) ;;
            *) printf '%s\n' "$value"; return 0 ;;
        esac
    done
    printf 'unknown\n'
}

state_label() {
    case "$1" in
        0) printf '经典低频闪\n' ;;
        2) printf '全亮度低频闪\n' ;;
        1) printf '中间状态/系统保留\n' ;;
        *) printf '未知\n' ;;
    esac
}
