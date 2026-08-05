# 更新日志

## V5.3.1

- 默认不再写入运行日志和状态文件，减少 `/data/local/tmp` 下的可见调试痕迹。
- 将 pid/stamp 等运行控制文件迁移到模块目录 `/data/adb/modules/oplus_smart_dimming/run/`。
- `state`、`boot.log` 和 `smart_dimming.log` 仅在模块目录 `settings.prop` 中启用 `debug_logging=1` 时写入。

## V5.3.0

- 刷入时通过音量键选择亮屏守护模式：音量+ 为稳定轮询模式，音量- 为 logcat 实验模式。
- 运行时强制 `poll` / `logcat` 二选一，只读取模块目录内的安装选择，旧版 `/storage/emulated/0/Documents/Oplus_Smart_Dimming/settings.prop` 不再影响模式。
- logcat 模式改为事件驱动：亮屏监听 ColorOS `RefreshRate` / `OplusVrrScenePolicy` / `VRR` 相关日志，命中后再确认 setting 和刷新率；息屏后停止刷新率监听，只保留 `screen_toggled`。
- 修复 logcat 模式在息屏/重新亮屏后可能残留旧 `RefreshRate` logcat 子进程的问题，避免孤儿监听增加后台功耗。
- 补充 Android 多用户处理：读取 setting 时遍历系统用户；恢复时对可读写用户写回 `2`，兼容应用分身常见的 `user 999` 场景。
- 安装阶段增加设备兼容性检查：读取 `display_single_pulse_eyeprotection_switch`，确认系统暴露了本模块依赖的 ColorOS 调光设置。
- 如果未检测到 `经典低频闪` / `全亮度低频闪` 对应的底层设置值，安装会直接终止并提示原因，避免刷入到不支持的设备。
- 实机验证：必剪 90Hz、桌面 120Hz、王者荣耀 144Hz、息屏/亮屏切换均符合预期。

## V5.2.9

- 修复 logcat 模式在息屏/重新亮屏后可能残留旧 `RefreshRate` logcat 子进程的问题。
- 停止 guard 时会先清理子进程树，并清理残留刷新率 logcat，避免模式二因为孤儿监听进程增加后台功耗。
- 清理运行配置残留：`/storage/emulated/0/Documents/Oplus_Smart_Dimming/settings.prop` 不再参与模式选择和运行判断，代码中移除旧配置读取路径。

## V5.2.8

- logcat 模式移除 `mkfifo`，避免 ColorOS/SELinux 拒绝 system logcat 读取 `/data/local/tmp` FIFO。
- `display_single_pulse_eyeprotection_switch` 读取增加 `settings` / `cmd settings` 多路径兜底，降低 KernelSU service 环境读成 `-1` 的概率。
- 恢复写回也增加 `cmd settings` 兜底；模式二仍然只由 logcat 事件触发，不启用 3 秒轮询。

## V5.2.7

- 服务内调用 Android 系统命令改为绝对路径，避免 KernelSU/busybox service 环境下 `settings`、`cmd`、`dumpsys` 解析失败导致状态读成 `-1`。
- 模块运行状态不再依赖 `/storage/emulated/0/Documents/Oplus_Smart_Dimming/settings.prop`，避免旧 WebUI 配置文件权限和历史内容影响判断。
- logcat 模式继续保持事件驱动，不启用 3 秒轮询。

## V5.2.6

- 修复旧版运行配置可能残留 `WebUI 设置` 文案的问题，服务启动时会用当前格式原子重写运行状态文件。
- logcat 模式补充适配 ColorOS 16 实机日志：`Trigger app switch boost`、`setDisplayConfigSpecs complete`、`startAppSwitchBoost`、`currDisplayRate=`、`targetMode=` 等刷新率事件。
- 状态文件新增 `selected_guard_mode`，启动日志新增模块版本，方便确认当前实际运行模式。
- 模式二仍不启用 3 秒轮询，只由 `screen_toggled` 和刷新率 logcat 事件驱动。

## V5.2.5

- 强制 `poll` / `logcat` 二选一：运行时只读取刷入阶段写入模块目录的安装选择，不再允许运行配置切换到另一套逻辑。
- 安装选择改为脚本加载时立即执行，并在 `on_install()` 中做幂等确认，适配部分 KernelSU Hybrid Mount 环境不进入 `on_install()` 的情况。
- 保留标准 `chooseport`，缺失时才回退到 `getevent` 监听音量键。

## V5.2.4

- 恢复刷入时音量键选择模式，按 Magisk/KernelSU 标准 `chooseport` 写法实现。
- 音量+ 选择稳定 `guard_mode=poll`，音量- 选择实验 `guard_mode=logcat`。
- 安装选择先写入模块目录 `settings.prop`，避免刷入阶段依赖 `/sdcard` 可写；服务首次启动后再同步到运行配置目录。

## V5.2.3

- 移除安装时音量键选择模式，恢复无交互标准安装流程。
- 原因：实测 KernelSU Hybrid Mount 环境可能不显示 `customize.sh` 里的音量键提示，甚至导致刷入失败。
- 默认使用 `guard_mode=poll`，logcat 实验模式改为安装后通过 `/storage/emulated/0/Documents/Oplus_Smart_Dimming/settings.prop` 手动切换。
- 打包脚本改为从 `module.prop` 自动生成 release 包名，减少版本号和包名不一致。

## V5.2.2

- 修复 V5.2.1 在部分 KernelSU/Hybrid Mount 安装环境下因 `SKIPUNZIP=1` 导致无法刷入的问题。
- 保留 `guard_mode=poll/logcat` 配置能力。

## V5.2.1

- 修复安装时可能跳过音量键模式选择的问题。
- 模式选择改为每次安装都询问，且在解压模块文件前显示，避免被安装日志淹没。

## V5.2.0

新增可选守护模式：

- `guard_mode=poll`：默认稳定方案，沿用 V5.0.0 的亮屏低频检查。
- `guard_mode=logcat`：实验省电方案，监听 ColorOS 的 `RefreshRate` / `OplusVrrScenePolicy` / `VRR` 日志，在刷新率或调光状态变化时触发确认。

安装时通过音量键选择：

- 音量+：稳定轮询模式。
- 音量-：logcat 实验模式。

配置文件：

```text
/storage/emulated/0/Documents/Oplus_Smart_Dimming/settings.prop
```

V5.2.0 同时补上 Android 多用户 settings 处理。双开/应用分身可能使用非 `user 0` 的 settings 命名空间，所以模块会遍历系统用户读取 `display_single_pulse_eyeprotection_switch`；恢复时也会对存在该设置的用户写回 `2`。

logcat 模式仍是实验选项。它比轮询更省电，但依赖 ColorOS 私有日志，可靠性不如默认 `poll`。后续系统更新、日志 tag 变化、日志等级变化、多开/应用分身用户差异，都可能导致无法触发、无法读取或无法写回。

## V5.0.0

V5.0.0 是一次策略重写：从 4.x 的“按应用包名切换”改为“按刷新率恢复”。

### 为什么不继续沿用 4.x

4.x 需要维护应用名单和 WebUI，并监听前台应用变化。这个方案能工作，但它解决的是“哪个应用需要切换”的问题，而 ColorOS 16 的真实问题不是包名。

实机表现是：

- 进入 `144Hz+` 场景时，系统会自己把调光状态切到经典低频闪。
- 退出 `144Hz+` 场景、回到 `120Hz` 及以下后，系统可能不会恢复全亮度低频闪。
- 同一个应用内可能有多个刷新率场景，包名名单无法准确判断。
- WebUI、应用名单、前台应用监听、native 守护都会带来额外复杂度和功耗。

因此 V5.0.0 不再主动按应用切换调光状态，只在系统已经切到 `0` 后，判断当前刷新率是否已经回到 `120Hz` 及以下。如果是，则恢复到 `2`。

### V5.0.0 行为

- `144Hz+`：不干预，保留系统切到经典低频闪的行为。
- `120Hz` 及以下：如果当前仍是 `0`，恢复到 `2`。
- 当前已经是 `2`：不读取刷新率，不写设置。
- 息屏：停止刷新率守护，只保留亮灭事件监听。
- 亮屏：重新启动低频刷新率守护。

### 相比 4.x 删除的内容

- WebUI。
- Action 入口。
- 应用名单配置。
- 前台应用包名解析。
- cpuset/inotify 应用监听链路。
- native/C++ 守护进程。
- 旧版 shell fallback 脚本。

### 保留的取舍

V5.0.0 没有采用完全 logcat 驱动的刷新率事件监听。完全事件驱动更省电，但依赖 ColorOS 私有日志，双开用户和日志 tag 变化也会带来不确定性。

当前稳定版选择更保守的低频检查：

- 亮屏每 3 秒读取一次 setting。
- 只有 setting 为 `0` 时才读取刷新率。
- 息屏不做刷新率检查。

这个方案比 4.x 简单，也比旧 native 方案更轻，同时保留了更好的可靠性。
