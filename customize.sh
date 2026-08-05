SKIPMOUNT=false
PROPFILE=false
POSTFSDATA=false
LATESTARTSERVICE=true
SETTING_KEY="display_single_pulse_eyeprotection_switch"
SUPPORT_CHECK_DONE=false
GUARD_MODE=""
GUARD_MODE_SELECTED=false

print_modname() {
  ui_print "*******************************"
  ui_print "      欧加真智能调光"
  ui_print "  ColorOS 16 refresh guard"
  ui_print "*******************************"
}

on_install() {
  assert_device_supported
  ensure_guard_mode_selected
  ui_print "- Extracting module files"
  unzip -o "$ZIPFILE" -x 'META-INF/*' -d "$MODPATH" >&2
  write_install_config
}

read_secure_setting() {
  user_id="$1"

  value=$(/system/bin/settings --user "$user_id" get secure "$SETTING_KEY" 2>/dev/null)
  case "$value" in
    0|1|2) echo "$value"; return 0 ;;
  esac

  value=$(/system/bin/cmd settings get --user "$user_id" secure "$SETTING_KEY" 2>/dev/null)
  case "$value" in
    0|1|2) echo "$value"; return 0 ;;
  esac

  if [ "$user_id" = "0" ]; then
    value=$(/system/bin/settings get secure "$SETTING_KEY" 2>/dev/null)
    case "$value" in
      0|1|2) echo "$value"; return 0 ;;
    esac

    value=$(/system/bin/cmd settings get secure "$SETTING_KEY" 2>/dev/null)
    case "$value" in
      0|1|2) echo "$value"; return 0 ;;
    esac
  fi

  echo "unknown"
  return 1
}

assert_device_supported() {
  [ "$SUPPORT_CHECK_DONE" = "true" ] && return 0

  ui_print "- 检查设备调光选项"
  dimming_value=$(read_secure_setting 0)

  case "$dimming_value" in
    0)
      ui_print "  已检测到：经典低频闪"
      ;;
    2)
      ui_print "  已检测到：全亮度低频闪"
      ;;
    *)
      ui_print "  未检测到本模块需要的 ColorOS 调光设置项"
      ui_print "  需要系统同时支持："
      ui_print "    经典低频闪：$SETTING_KEY=0"
      ui_print "    全亮度低频闪：$SETTING_KEY=2"
      ui_print "  当前读取结果：$SETTING_KEY=$dimming_value"
      abort "! 设备不支持或系统未暴露对应选项，已停止安装"
      ;;
  esac

  SUPPORT_CHECK_DONE=true
}

ensure_guard_mode_selected() {
  [ "$GUARD_MODE_SELECTED" = "true" ] && return 0
  assert_device_supported
  select_guard_mode
}

select_guard_mode() {
  ui_print "- 请选择亮屏守护模式"
  ui_print "  音量+：稳定轮询模式"
  ui_print "    亮屏每 3 秒低频读取 setting，setting=0 时才读取刷新率"
  ui_print "  音量-：logcat 实验模式"
  ui_print "    监听 ColorOS RefreshRate/VRR 日志，功耗更低但不稳定"
  ui_print "    局限：系统更新可能改日志；日志被关闭会失效；多开/分身用户可能无法完整读取或写回"
  ui_print "- 请按音量键选择"

  if type chooseport >/dev/null 2>&1; then
    if chooseport; then
      GUARD_MODE="poll"
      ui_print "- 已选择：稳定轮询模式"
    else
      GUARD_MODE="logcat"
      ui_print "- 已选择：logcat 实验模式"
    fi
  elif wait_volume_key; then
    GUARD_MODE="poll"
    ui_print "- 已选择：稳定轮询模式"
  else
    GUARD_MODE="logcat"
    ui_print "- 已选择：logcat 实验模式"
  fi

  GUARD_MODE_SELECTED=true
  write_install_config
}

wait_volume_key() {
  while true; do
    key_event=$(getevent -l -q -c 1 2>/dev/null)
    case "$key_event" in
      *KEY_VOLUMEUP*DOWN*) return 0 ;;
      *KEY_VOLUMEDOWN*DOWN*) return 1 ;;
    esac
  done
}

write_install_config() {
  [ -n "$MODPATH" ] || return 0
  [ -n "$GUARD_MODE" ] || GUARD_MODE="poll"

  {
    echo "# 欧加真智能调光 - 安装选择"
    echo "# guard_mode=poll：稳定模式，亮屏每 3 秒低频读取 setting"
    echo "# guard_mode=logcat：实验模式，监听 ColorOS 刷新率日志，可能因系统更新、日志变化或多开用户行为失效"
    echo "guard_mode=$GUARD_MODE"
    echo "debug_logging=0"
  } > "$MODPATH/settings.prop"
}

set_permissions() {
  set_perm "$MODPATH" 0 0 0755

  [ -f "$MODPATH/module.prop" ] && set_perm "$MODPATH/module.prop" 0 0 0644
  [ -f "$MODPATH/customize.sh" ] && set_perm "$MODPATH/customize.sh" 0 0 0644
  [ -f "$MODPATH/settings.prop" ] && set_perm "$MODPATH/settings.prop" 0 0 0644
  [ -d "$MODPATH/run" ] && set_perm_recursive "$MODPATH/run" 0 0 0755 0644
  [ -d "$MODPATH/META-INF" ] && set_perm_recursive "$MODPATH/META-INF" 0 0 0755 0644

  if [ -d "$MODPATH/scripts" ]; then
    set_perm_recursive "$MODPATH/scripts" 0 0 0755 0755
  fi

  [ -f "$MODPATH/service.sh" ] && set_perm "$MODPATH/service.sh" 0 0 0755
}

assert_device_supported
ensure_guard_mode_selected
