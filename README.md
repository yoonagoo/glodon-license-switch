# 广联达与 Virbox 开关

Windows 下的 PowerShell 菜单，用来暂停或恢复广联达和 SenseShield/Virbox 的常驻组件。

## 使用方法

下载 [中文启动器压缩包](https://github.com/yoonagoo/glodon-license-switch/releases/latest/download/GlodonLicenseSwitch-zh-CN.zip)，解压后双击 **广联达与 Virbox 开关.exe**。也可以运行同名的 CMD 版本。EXE 自带图标，两个版本均可单独使用。每次打开都会先查询 GitHub 主分支的最新提交，按提交号下载脚本后再打开菜单。

原来的 [CMD 直接下载链接](https://github.com/yoonagoo/glodon-license-switch/releases/latest/download/GlodonLicenseSwitch-Launcher.cmd) 继续可用。

也可以在项目目录打开 PowerShell，直接运行脚本：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\GlodonLicenseSwitch.ps1
```

确认管理员提示后，菜单会显示总状态、相关进程及 PID、服务和驱动的启动方式，以及登录启动项。

| 按键 | 操作 |
| --- | --- |
| `1` | 恢复原有启动设置，并启动关闭前正在运行的服务和驱动。 |
| `2` | 停止并禁用目标服务和驱动，暂停登录启动项。该设置在重启后仍然有效。 |
| `0` | 退出菜单。 |

菜单会检查 PowerShell、Windows 服务管理组件、相关服务和驱动以及对应程序文件。缺少服务或驱动注册、或路径不受支持时，菜单会列出问题。文件缺失会单独提示。注册信息正常时，仍可关闭对应项目。

只查看当前状态时，可以加 `-Action Status`，无需提升为管理员。

## 适用范围

- 需要 64 位 Windows 和 64 位 Windows PowerShell 5.1。在 Windows 11 上验证过。
- 服务：`GTJLaunchService`、`gcpsvc`、`GSCService`、`gssvc`、`SSMonitorService`、`Sense Shield Service`、`Virbox License Control Center`。
- GTJ2026 支持位于 64 位 Program Files 下的 `Glodon\GTJ2026`，以及 32 位 Program Files 下的 `GrandSoft\GTJ2026`。
- 驱动：`elite5`、`sprotect2`、`slock2`。登录启动项：`GSCServer`、`GWS`。
- 脚本会校验这套服务名称和程序路径。组件缺失、安装路径或服务名称不同的机器，可能需要先适配脚本。驱动仍在加载时，菜单会提示是否需要重启。

首次关闭时，脚本把原有配置写入 `%LOCALAPPDATA%\GlodonLicenseSwitch\original-state.json`。需要恢复时请保留该文件。同一 Windows 用户从不同仓库目录运行脚本，会使用同一份恢复记录。

## 构建中文启动器

在项目目录用 64 位 Windows PowerShell 运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-Launcher.ps1
```

产物保存在 dist 目录，包括中文 EXE、CMD 和发布压缩包。
