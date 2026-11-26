# 广联达与 Virbox 开关

Windows 下的 PowerShell 菜单，用来暂停或恢复广联达和 SenseShield/Virbox 的常驻组件。

## 使用方法

在项目目录打开 PowerShell，运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\GlodonLicenseSwitch.ps1
```

确认管理员提示后，菜单会显示总状态、相关进程及 PID、服务和驱动的启动方式，以及登录启动项。

| 按键 | 操作 |
| --- | --- |
| `1` | 恢复原有启动设置，并启动关闭前正在运行的服务和驱动。 |
| `2` | 停止并禁用目标服务和驱动，暂停登录启动项。该设置在重启后仍然有效。 |
| `0` | 退出菜单。 |

只查看当前状态时，可以加 `-Action Status`，无需提升为管理员。

## 适用范围

- 需要 64 位 Windows 和 64 位 Windows PowerShell 5.1。在 Windows 11 上验证过。
- 服务：`GTJLaunchService`、`gcpsvc`、`GSCService`、`gssvc`、`SSMonitorService`、`Sense Shield Service`、`Virbox License Control Center`。
- GTJ2026 支持位于 64 位 Program Files 下的 `Glodon\GTJ2026`，以及 32 位 Program Files 下的 `GrandSoft\GTJ2026`。
- 驱动：`elite5`、`sprotect2`、`slock2`。登录启动项：`GSCServer`、`GWS`。
- 脚本会校验这套服务名称和程序路径。组件缺失、安装路径或服务名称不同的机器，可能需要先适配脚本。驱动仍在加载时，菜单会提示是否需要重启。

首次关闭时，脚本把原有配置写入 `%LOCALAPPDATA%\GlodonLicenseSwitch\original-state.json`。需要恢复时请保留该文件。同一 Windows 用户从不同仓库目录运行脚本，会使用同一份恢复记录。
