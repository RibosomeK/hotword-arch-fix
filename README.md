# Hotword Arch Fix

作者：Claude

一个 LSPosed 模块，用于修复 OnePlus 15R（OxygenOS 16 / Android 16）上
Google 应用无法使用 DSP 熄屏 "Hey Google" 热词的问题。

> 本模块只包含“熄屏唤醒修复”。Gemini Live 的锁屏进入 / 默认 Live 功能在
> 另一个独立项目 [gemini-live-tweaks](../gemini-live-tweaks/) 中。

## 功能

OxygenOS 16.0.5.701 的 Qualcomm SoundTrigger HAL 上报的
`supportedModelArch` 为空。Google 应用会把该字段与一份 DSP 平台 ID 白名单
比对，空值导致它判定 DSP 热词不可用，从而在熄屏时停止监听。

只伪造该字段还不够：AOSP 的 `SoundTriggerManager` 在 attach 时会经过
system_server 的 `SoundTriggerService.newSoundTriggerHelper()`，后者重新
枚举模块并用 `ModuleProperties.equals()` 比较。OEM 构建中客户端和服务端
两份列表并不相等，会抛出 `Invalid module properties`。

模块做两件事：

1. 在 Google 应用进程内，把空的 `supportedModelArch` 伪装成白名单值
   `259,0e01b779-79f1-3b55-ab94-1feb46ad70ef`（保留 AOSP fake HAL 模块的
   `injection` 值不动）。
2. 在 system_server 内，在 `newSoundTriggerHelper()` 执行前，把传入的
   `ModuleProperties` 替换为服务端自己列表中的同 ID 对象，使 `contains()`
   校验通过。

模块还修正了 `ISoundTriggerService` 调用前的客户端 Identity（uid/pid），
保持与已验证配置一致。

## 适用环境

- 已安装 LSPosed（已测试 LSPosed 2.2.1 / API 102）。
- OnePlus 15R `CPH2769`，OxygenOS `16.0.5.701(EX01)`，Android 16（SDK 36）。
- Google 应用 `17.68.28.ve.arm64`（其他版本可能类名/行为不同）。

这不是通用修复：它针对的是该 OEM HAL 的 `supportedModelArch` 缺失问题。
其他设备或系统更新后可能不需要、也可能不适用。

## 安装与使用

1. 安装 `build/HotwordArchFix.apk`。
2. 打开 LSPosed 管理器，启用 **Hotword Arch Fix**。
3. 作用域勾选：
   - Google（`com.google.android.googlequicksearchbox`）
   - System Framework / 系统框架（system_server，LSPosed 中显示为
     System Framework，数据库键为 `system`）
4. 重启手机。system_server 作用域必须重启才能加载；仅重启 Google 应用
   不足以加载 system_server 钩子。
5. 熄屏后说 “Hey Google” 测试。成功时可在日志中看到
   `SoundTriggerHelper: startRecognition successful` 以及 DSP 热词检测。

更新模块 APK 后需要重新加载目标进程（system_server 作用域需要重启）。
如果只是普通 `adb install -r`，请务必加 `--no-incremental`：

```bash
adb install --no-incremental -r HotwordArchFix.apk
```

否则 APK 可能被增量安装到 `incremental-fs`，开机早期 LSPosed 读取不到
APK，system_server 钩子会加载失败（详见“警告”）。

## 构建

依赖：

- JDK 17+（`javac`、`jar`、`keytool`）
- Android SDK Platform 36（`android.jar`）
- Android build-tools，包含 `aapt2`、`d8`、`zipalign`、`apksigner`
- Python 3
- 本仓库 `libs/api-82.jar`（Xposed API 82，已包含）

示例：

```bash
export JAVA_HOME=/path/to/jdk17
export ANDROID_HOME=/path/to/Android/Sdk

./build.sh
```

也可以直接指定各项路径：

```bash
ANDROID_JAR=/path/to/android-36/android.jar \
BUILD_TOOLS=/path/to/build-tools/36.0.0 \
XPOSED_JAR=libs/api-82.jar \
./build.sh
```

输出：`build/HotwordArchFix.apk`。

仓库内 `keystore/debug.keystore` 是公开的调试签名，仅用于保证模块更新时
签名一致；不要用于正式发布。如果删除它，`build.sh` 会生成一个新的调试
密钥，届时旧版本模块需要先卸载再安装（签名不同）。

## 警告

- 需要 LSPosed。模块在 system_server 中运行钩子，存在导致系统服务异常的
  风险；仅在你自己的测试设备上使用，并自行承担风险。
- 仅针对 OnePlus 15R / OxygenOS 16 的 SoundTrigger HAL 问题，不保证适用
  于其他设备、ROM 或 OTA 版本。
- 这是 Workaround：如果系统更新修复了 HAL，本模块将不再需要；升级后请
  先禁用模块验证。
- 不要在本模块里调用 `AlwaysOnHotwordDetector` 的
  `queryParameter`/`getParameter`/`setParameter`。该 Qualcomm HAL 不支持
  阈值参数，AOSP 的 `SoundTriggerHalEnforcer` 会把错误当成 HAL 故障并重启
  音频 HAL，导致亮屏和熄屏热词全部失效。
- APK 更新后 LSPosed 可能缓存旧路径。开机前请确认 LSPosed 数据库中的
  module `apk_path` 与 `pm path moe.debug.hotwordarch` 一致；使用
  `--no-incremental` 并重启目标进程可以减少相关故障。
- 禁用/卸载模块并重启即可回滚。
- 本仓库不包含 Gemini Live 功能，也没有从 Google 获取任何私有 API 授权；
  仅供个人设备兼容性研究使用。按现状提供，无任何担保。
