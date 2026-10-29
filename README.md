# Hotword Arch Fix

作者：DeepSeek

一个 LSPosed 模块，修复 OnePlus 15R（OxygenOS 16 / Android 16）上 Google
应用无法使用 DSP 熄屏 “Hey Google” 的问题。

## 功能

该 OEM 的 SoundTrigger HAL 上报空的 `supportedModelArch`，Google 应用因此
判定 DSP 热词不可用。模块做两件事：

1. 在 Google 应用进程内，把空的 `supportedModelArch` 伪装成白名单值。
2. 在 system_server 内，替换 `SoundTriggerService.newSoundTriggerHelper()`
   的参数为服务端自己列表中的同 ID 对象，使 `ModuleProperties.equals()`
   校验通过。

模块只处理熄屏热词，不涉及助手界面或其它功能。

## 适用环境

- 已安装 LSPosed。
- OnePlus 15R `CPH2769`，OxygenOS `16.0.5.701(EX01)`，Android 16。
- Google 应用 `17.68.28.ve.arm64`。

仅针对该 OEM HAL 的空 `supportedModelArch` 问题，不保证适用于其它设备或
系统版本。

## 安装

1. 安装 `build/HotwordArchFix.apk`。
2. 在 LSPosed 管理器中启用 **Hotword Arch Fix**。
3. 作用域勾选 Google（`com.google.android.googlequicksearchbox`）和
   System Framework。
4. 重启手机（system_server 钩子需要重启才能加载）。
5. 熄屏后说 “Hey Google” 测试。

更新模块时使用：

```bash
adb install --no-incremental -r HotwordArchFix.apk
```

更新后重启手机，避免 LSPosed 使用旧的模块路径或 system_server 残留旧代码。

## 构建

依赖：

- JDK 17+（`javac`、`jar`、`keytool`）
- Android SDK Platform 36（`android.jar`）
- Android build-tools（`aapt2`、`d8`、`zipalign`、`apksigner`）
- Python 3
- `libs/api-82.jar`（Xposed API 82，已包含）

```bash
export JAVA_HOME=/path/to/jdk17
export ANDROID_HOME=/path/to/Android/Sdk
./build.sh
```

或显式指定：

```bash
ANDROID_JAR=/path/to/android-36/android.jar \
BUILD_TOOLS=/path/to/build-tools/36.0.0 \
./build.sh
```

输出：`build/HotwordArchFix.apk`。

仓库内的调试签名仅用于模块更新一致性，不要用于正式发布。

## 警告

- 模块包含 system_server 钩子，存在系统服务异常风险；仅在自己的测试设备上
  使用，并自行承担风险。
- 仅适用于 OnePlus 15R / OxygenOS 16 的上述 HAL 问题；系统更新后可能失效。
- 不要调用 `AlwaysOnHotwordDetector` 的阈值参数 API。该 HAL 不支持参数
  调整，错误会被当成 HAL 故障并重启音频 HAL。
- `adb install` 请使用 `--no-incremental`；更新后重启手机。
- 禁用/卸载模块并重启即可回滚。
- 按现状提供，无任何担保。本项目与 Google 无关。

## License

本项目代码采用 WTFPL v2 授权，完整文本见 [LICENSE](LICENSE)。

注意：`libs/api-82.jar` 是 Xposed API 82，仍遵循其原始 Apache-2.0
许可，不适用本项目的 WTFPL。
