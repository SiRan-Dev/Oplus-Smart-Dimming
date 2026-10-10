# 欧加真智能调光

一加 / 欧加系 ColorOS 16 的低频闪状态恢复模块。

ColorOS 16 在进入 `144Hz+` 场景时会把调光状态切到 `经典低频闪`，但退出高刷场景回到 `120Hz` 及以下后，系统不会稳定恢复 `全亮度低频闪`。本模块只修这个回退缺口。

## 适用范围

仅适用于系统设置中同时存在以下两个选项，且底层设置值符合当前机型行为的设备：

- `经典低频闪`：`display_single_pulse_eyeprotection_switch=0`
- `全亮度低频闪`：`display_single_pulse_eyeprotection_switch=2`

安装时会读取 `display_single_pulse_eyeprotection_switch` 做兼容性检查。如果系统没有暴露这个设置项，或当前值不是已验证的 `0/2`，安装会直接终止并提示原因。

当前验证设备：

- OnePlus 15 / PLK110
- ColorOS 16

## 工作方式

V5 不再按应用包名切换，也不再提供 WebUI。

守护进程只做一件事：

1. 息屏时保持空闲。
2. 亮屏时读取当前刷新率和调光设置。
3. 如果刷新率 `>120Hz`，尊重系统行为，不干预经典低频闪。
4. 如果刷新率 `<=120Hz` 且当前状态仍是 `0`，写回 `2`。
5. 如果已经是 `2`，不写设置。

这样可以避免和系统在高刷场景互相抢写，同时修复回到 120Hz 后卡在经典调光的问题。

默认亮屏检测采用低频守护：

- 每 3 秒读取一次 `display_single_pulse_eyeprotection_switch`。
- 当前值是 `2` 时直接休眠，不读取刷新率。
- 只有当前值是 `0` 时，才读取刷新率并判断是否恢复。

息屏后刷新率守护会停止，只保留 `screen_toggled` 事件监听，亮屏后再重新启动。

刷入模块时会要求用音量键选择亮屏守护模式：

- 音量+：稳定轮询模式，也就是 `guard_mode=poll`。
- 音量-：logcat 实验模式，也就是 `guard_mode=logcat`。

选择会写入模块目录内的 `settings.prop`。运行时只读取这个安装选择，`poll` 和 `logcat` 两套亮屏守护逻辑只会生效其中一种。旧版曾使用的 `/storage/emulated/0/Documents/Oplus_Smart_Dimming/settings.prop` 不再参与模式选择和运行判断。

```text
guard_mode=poll
```

两种模式含义：

- `poll`：稳定模式。亮屏低频读取 setting，可靠性更高。
- `logcat`：实验省电模式。监听 ColorOS 的 `RefreshRate` / `OplusVrrScenePolicy` / `VRR` 日志，命中刷新率或调光事件后再确认状态。

logcat 模式的局限性：

- 依赖 ColorOS 私有日志，后续系统更新可能改掉 tag 或日志内容，导致触发失败。
- 如果系统关闭或降级相关 debug 日志，模块可能收不到刷新率变化事件。
- 多开/应用分身可能使用独立 Android 用户，模块会尽量遍历多用户读写 setting，但仍可能遇到无法完整读取或写回的设备差异。
- 首次进入某些场景时可能存在过渡刷新率日志，需要等待事件后的确认结果。

只追求稳定时选择音量+ 或保持 `guard_mode=poll` 即可。

## 为什么从 4.x 改成 V5

4.x 的核心思路是“按应用包名切换”：进入名单应用切到经典低频闪，退出后恢复全亮度低频闪。这个方向后来被实机行为证明不够准确。

ColorOS 16 真正触发经典调光回退的关键不是包名，而是刷新率场景：

- 进入 `144Hz+` 场景时，系统会主动切到经典低频闪。
- 回到 `120Hz` 及以下后，系统不一定恢复全亮度低频闪。
- 同一个应用内也可能有不同刷新率页面，仅靠包名无法准确表达。
- 应用名单、WebUI、前台应用监听都会增加复杂度和后台负担。

V5 因此只补系统缺失的“恢复”动作：高刷时不干预，回到 120Hz 及以下且状态仍卡在 `0` 时才写回 `2`。

## 为什么砍掉 WebUI 和应用名单

旧版按包名维护名单，但真实触发条件不是 App，而是刷新率：

- 同一个 App 内不同页面可能刷新率不同。
- 游戏、系统动画、视频、桌面都可能动态切刷新率。
- 用户维护包名名单既不精确，也增加后台监听和配置复杂度。

V5 直接看刷新率，逻辑更短，也更省电。

## 打包

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\package_release.ps1
```

当前 release 包名：

```text
build/oplus_smart_dimming_v531_release.zip
```

## 调试

默认不写运行日志和状态文件，运行所需的 pid/stamp 文件保存在模块目录：

```text
/data/adb/modules/oplus_smart_dimming/run/
```

仅在模块目录 `settings.prop` 中启用 `debug_logging=1` 时，才会额外写入：

- `/data/adb/modules/oplus_smart_dimming/run/state`
- `/data/adb/modules/oplus_smart_dimming/run/boot.log`
- `/storage/emulated/0/Documents/Oplus_Smart_Dimming/smart_dimming.log`

重点字段：

- `current_state`
- `refresh_rate`
- `restored_default`
- `runtime_mode`
- `screen_on`
- `note`

## V5.3.1 实机验证清单

安装新包后建议逐项确认：

- 刷入时能通过音量键选择 `poll` 或 `logcat` 模式。
- 模块目录 `settings.prop` 中的 `guard_mode` 与刷入选择一致。
- 重启后后台守护进程自动启动。
- `/data/adb/modules/oplus_smart_dimming/run/` 下只保留 pid/stamp 运行文件。
- 默认 `debug_logging=0` 时不写 `state`、`boot.log` 和 `smart_dimming.log`。
- `/data/local/tmp/` 下没有本模块旧版残留文件。
- 120Hz 及以下时，如果状态卡在 `0`，能恢复到 `2`。
- 144Hz+ 场景下不强行写回 `2`。
- 息屏时刷新率守护停止，只保留亮屏事件监听。

## 致谢

- [YC9559 / dfps](https://github.com/yc9559/dfps)  
  前台应用检测与事件驱动思路的重要参考来源
