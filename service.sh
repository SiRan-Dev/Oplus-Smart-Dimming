#!/system/bin/sh

MODDIR=${0%/*}
. "$MODDIR/scripts/common.sh"

SCREEN_ON_CHECK_SEC=3
EVENT_CONFIRM_DELAY_SEC=1
EVENT_THROTTLE_SEC=2

chmod 0755 "$MODDIR/service.sh" 2>/dev/null
chmod 0755 "$MODDIR"/scripts/*.sh 2>/dev/null

current_timestamp() {
    date '+%Y-%m-%d %H:%M:%S' 2>/dev/null
}

write_runtime_file() {
    path="$1"
    value="$2"

    ensure_run_dir || return 1
    printf '%s\n' "$value" > "$path" || return 1
    chmod 0644 "$path" 2>/dev/null
}

cleanup_legacy_tmp_files() {
    rm -f \
        /data/local/tmp/oplus_smart_dimming.pid \
        /data/local/tmp/oplus_smart_dimming.guard.pid \
        /data/local/tmp/oplus_smart_dimming.logcat.pid \
        /data/local/tmp/oplus_smart_dimming.refresh_event.stamp \
        /data/local/tmp/oplus_smart_dimming.state \
        /data/local/tmp/oplus_smart_dimming.state.tmp \
        /data/local/tmp/oplus_smart_dimming.boot.log 2>/dev/null
}

is_screen_on() {
    [ "$(read_dpms)" = "On" ]
}

is_rate_at_most_120() {
    rate="$1"
    case "$rate" in
        ''|unknown|*[!0-9.]*)
            return 1
            ;;
    esac
    awk "BEGIN { exit !($rate <= 120.5) }" >/dev/null 2>&1
}

write_state() {
    [ "$DEBUG_LOG_ENABLED" = "1" ] || return 0

    current_state="$1"
    refresh_rate="$2"
    restored_default="$3"
    runtime_mode="$4"
    screen_on="$5"
    note="$6"

    tmp="${STATE_FILE}.tmp"
    {
        echo "current_state=$current_state"
        echo "refresh_rate=$refresh_rate"
        echo "restored_default=$restored_default"
        echo "runtime_mode=$runtime_mode"
        echo "selected_guard_mode=$GUARD_MODE"
        echo "screen_on=$screen_on"
        echo "note=$note"
        echo "last_update=$(current_timestamp)"
    } > "$tmp" && mv "$tmp" "$STATE_FILE"
    chmod 0644 "$STATE_FILE" 2>/dev/null
}

publish_if_changed() {
    snapshot="$1"
    if [ "$snapshot" = "$LAST_STATE_SNAPSHOT" ]; then
        return 0
    fi

    LAST_STATE_SNAPSHOT="$snapshot"
    IFS='|' read -r current_state refresh_rate restored_default runtime_mode screen_on note <<EOF
$snapshot
EOF
    write_state "$current_state" "$refresh_rate" "$restored_default" "$runtime_mode" "$screen_on" "$note"
}

publish_screen_off() {
    current_state=$(read_current_state)
    write_state "$current_state" "unknown" "0" "screen_off" "0" "screen off, refresh guard stopped"
}

run_refresh_check_once() {
    runtime_mode="${1:-refresh_guard}"
    current_state=$(read_current_state)
    refresh_rate="unknown"
    restored_default="0"
    note="setting already default, refresh probe skipped"

    if [ "$current_state" = "0" ]; then
        refresh_rate=$(read_refresh_rate)
        if is_rate_at_most_120 "$refresh_rate"; then
            if restore_default_state_all_users; then
                current_state="2"
                restored_default="1"
                runtime_mode="restore_default"
                note="setting=0 and refresh <=120Hz, restored full-brightness low flicker"
                log_debug "restore default: refresh=$refresh_rate"
            else
                runtime_mode="restore_failed"
                note="settings write failed"
                log_boot "settings write failed while restoring default state"
            fi
        else
            note="setting=0 but refresh >120Hz or unavailable, skipped"
        fi
    fi

    publish_if_changed "$current_state|$refresh_rate|$restored_default|$runtime_mode|1|$note"
}

poll_guard_loop() {
    LAST_STATE_SNAPSHOT=""
    log_boot "poll refresh guard loop started: pid=$$"

    while true; do
        if ! is_screen_on; then
            log_boot "poll refresh guard loop saw screen off, exiting: pid=$$"
            break
        fi

        run_refresh_check_once "poll_refresh_guard"
        sleep "$SCREEN_ON_CHECK_SEC"
    done
}

should_handle_refresh_event() {
    now=$(date '+%s' 2>/dev/null)
    case "$now" in
        ''|*[!0-9]*) return 0 ;;
    esac

    last=$(cat "$REFRESH_EVENT_STAMP_FILE" 2>/dev/null)
    case "$last" in
        ''|*[!0-9]*) last=0 ;;
    esac

    if [ $((now - last)) -lt "$EVENT_THROTTLE_SEC" ]; then
        return 1
    fi

    echo "$now" > "$REFRESH_EVENT_STAMP_FILE"
    chmod 0644 "$REFRESH_EVENT_STAMP_FILE" 2>/dev/null
    return 0
}

handle_refresh_log_event() {
    line="$1"
    case "$line" in
        *"display_single_pulse_eyeprotection_switch"*|\
        *"Refresh rate changing"*|\
        *"Trigger app switch boost"*|\
        *"setDisplayConfigSpecs complete"*|\
        *"startAppSwitchBoost"*|\
        *"initControlPanelRefreshRateData"*|\
        *"currDisplayRate="*|\
        *"targetMode="*|\
        *"maxRefreshRate="*|\
        *"setGameRefreshRate ["*|\
        *"notifyFrameRateChange"*|\
        *"handleConfigIdChange"*)
            ;;
        *)
            return 0
            ;;
    esac

    should_handle_refresh_event || return 0
    sleep "$EVENT_CONFIRM_DELAY_SEC"
    is_screen_on && run_refresh_check_once "logcat_refresh_guard"
}

logcat_guard_loop() {
    LAST_STATE_SNAPSHOT=""

    cleanup_logcat_guard() {
        rm -f "$REFRESH_EVENT_STAMP_FILE"
        exit 0
    }

    trap cleanup_logcat_guard INT TERM
    log_boot "logcat refresh guard loop started: pid=$$ tags=RefreshRate,OplusVrrScenePolicy,VRR"

    run_refresh_check_once "logcat_refresh_guard"

    while is_screen_on; do
        start_time=$(date '+%m-%d %H:%M:%S.000' 2>/dev/null)
        log_boot "starting refresh logcat listener from $start_time"

        /system/bin/logcat -b system -v brief -T "$start_time" -s RefreshRate:D OplusVrrScenePolicy:D VRR:D 2>/dev/null |
            while is_screen_on && IFS= read -r line; do
                handle_refresh_log_event "$line"
            done

        is_screen_on || break
        log_boot "refresh logcat listener exited, restarting"
        sleep 2
    done

    cleanup_logcat_guard
}

refresh_guard_loop() {
    case "$GUARD_MODE" in
        logcat) logcat_guard_loop ;;
        *) poll_guard_loop ;;
    esac
}

guard_alive() {
    [ -f "$GUARD_PID_FILE" ] || return 1
    guard_pid=$(cat "$GUARD_PID_FILE" 2>/dev/null)
    [ -n "$guard_pid" ] && [ -d "/proc/$guard_pid" ]
}

kill_child_processes() {
    parent_pid="$1"
    [ -n "$parent_pid" ] || return 0

    /system/bin/ps -A -o PID,PPID 2>/dev/null |
        while read -r child_pid child_ppid; do
            case "$child_pid:$child_ppid" in
                PID:*|'':*) continue ;;
            esac

            if [ "$child_ppid" = "$parent_pid" ]; then
                kill_child_processes "$child_pid"
                kill "$child_pid" 2>/dev/null
            fi
        done
}

cleanup_refresh_logcat_processes() {
    /system/bin/ps -A -o PID,ARGS 2>/dev/null |
        while IFS= read -r line; do
            case "$line" in
                *"logcat -b system"*"-s RefreshRate:D OplusVrrScenePolicy:D VRR:D"*)
                    pid=$(printf '%s\n' "$line" | awk '{print $1}')
                    case "$pid" in
                        ''|PID|*[!0-9]*) ;;
                        *) kill "$pid" 2>/dev/null ;;
                    esac
                    ;;
            esac
        done
}

start_guard() {
    if guard_alive; then
        return 0
    fi

    cleanup_refresh_logcat_processes
    refresh_guard_loop &
    guard_pid=$!
    write_runtime_file "$GUARD_PID_FILE" "$guard_pid"
    log_boot "screen on: refresh guard worker started pid=$guard_pid"
}

stop_guard() {
    if guard_alive; then
        guard_pid=$(cat "$GUARD_PID_FILE" 2>/dev/null)
        kill_child_processes "$guard_pid"
        kill "$guard_pid" 2>/dev/null
        sleep 1
        kill_child_processes "$guard_pid"
        [ -d "/proc/$guard_pid" ] && kill -TERM "$guard_pid" 2>/dev/null
        log_boot "screen off: refresh guard worker stopped pid=$guard_pid"
    fi

    cleanup_refresh_logcat_processes
    rm -f "$GUARD_PID_FILE" "$REFRESH_EVENT_STAMP_FILE"
    publish_screen_off
}

force_publish_state() {
    if is_screen_on; then
        run_refresh_check_once
    else
        publish_screen_off
    fi
}

cleanup() {
    log_boot "event service stopping"

    if [ -f "$LOGCAT_PID_FILE" ]; then
        logcat_pid=$(cat "$LOGCAT_PID_FILE" 2>/dev/null)
        [ -n "$logcat_pid" ] && kill "$logcat_pid" 2>/dev/null
    fi

    if guard_alive; then
        guard_pid=$(cat "$GUARD_PID_FILE" 2>/dev/null)
        kill_child_processes "$guard_pid"
        [ -n "$guard_pid" ] && kill "$guard_pid" 2>/dev/null
    fi

    cleanup_refresh_logcat_processes
    rm -f "$PID_FILE" "$GUARD_PID_FILE" "$LOGCAT_PID_FILE" "$REFRESH_EVENT_STAMP_FILE"
    exit 0
}

handle_screen_event() {
    event="$1"
    case "$event" in
        *"screen_toggled"*": 1"*)
            sleep 1
            if is_screen_on; then
                log_boot "event screen_toggled=1"
                start_guard
            fi
            ;;
        *"screen_toggled"*": 0"*)
            log_boot "event screen_toggled=0"
            stop_guard
            ;;
    esac
}

monitor_screen_events() {
    while true; do
        start_time=$(date '+%m-%d %H:%M:%S.000' 2>/dev/null)
        log_boot "starting screen_toggled event listener from $start_time"

        /system/bin/logcat -b events -v brief -T "$start_time" -s screen_toggled 2>/dev/null |
            while IFS= read -r line; do
                handle_screen_event "$line"
            done

        log_boot "screen_toggled event listener exited, restarting"
        sleep 2
    done
}

wait_for_boot
load_debug_config
cleanup_legacy_tmp_files

if service_alive; then
    existing_pid=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$existing_pid" ] && [ "$existing_pid" != "$$" ]; then
        log_boot "service already running: pid=$existing_pid, skip duplicate launcher pid=$$"
        exit 0
    fi
fi

trap cleanup INT TERM
trap force_publish_state USR1

write_runtime_file "$PID_FILE" "$$"
module_version=$(sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null | head -n 1)
[ -n "$module_version" ] || module_version="unknown"
log_boot "event service started: pid=$$ moddir=$MODDIR version=$module_version guard_mode=$GUARD_MODE"

if is_screen_on; then
    write_state "$(read_current_state)" "unknown" "0" "refresh_guard" "1" "screen on, guard_mode=$GUARD_MODE"
    start_guard
else
    stop_guard
fi

monitor_screen_events &
write_runtime_file "$LOGCAT_PID_FILE" "$!"
wait "$!"

cleanup
