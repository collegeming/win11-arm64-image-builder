# Windows 11 ARM64 镜像构建器：DroidVM 中文分支

本分支基于 [Droid-VM/win11-arm64-image-builder](https://github.com/Droid-VM/win11-arm64-image-builder)，使用微软官方 ARM64 ISO 和 DroidVM 修改版 Gunyah/VirtIO 驱动，生成 `.qcow2` 磁盘和可导入的 `.vmpkg`。主要路径是在 x64 Windows 上用 DISM 离线构建，支持简体中文资源保留和可选精简。

**Windows 11 专业版（Pro）26H2、Build 26300.9550，已集成 KB5124010，并在 Redmi K70 Pro 上进入中文桌面。** 构建时按真实版本信息选择和校验专业版；手机 `winver` 也确认了专业版、26H2 和 `26300.9550`。下载见[专业版 Release](https://github.com/collegeming/win11-arm64-image-builder/releases/tag/win11-pro-26H2-26300.9550-arm64-38108924414)，证据与未验证功能见 [K70 Pro 验证记录](docs/k70pro.md)。

## 目标与验收边界

| 项目 | 要求 / 证据 |
|---|---|
| 系统版本 | 目标 `26H2`，由 `windows/updates.json` 指定 |
| 系统构建号 | 目标 `26300.9550`，由 `windows/updates.json` 指定 |
| 版本选择 | 按映像元数据 `EditionID=Professional`、`Architecture=12`（ARM64）选择；匹配不唯一必须停止，不能回退到索引 1 |
| 更新包 | 必须使用 KB5124010 的官方 ARM64 包及所需前置包；在应用系统映像之后、`ResetBase` 之前安装 |
| 构建证据 | `image-metadata.json` 必须记录实际版本、EditionID、架构、构建号和更新包状态；实际值不能用目标值代填 |
| 待重启状态 | 如离线更新仍 pending，必须明确记录；首次启动并完成更新后，再核对实际构建号和包状态 |
| 手机验证 | K70 Pro 上的中文桌面与 `winver` 已确认 Pro / 26H2 / `26300.9550`；联网、USB、音频与长期稳定性未验证 |

以上是新 Pro 构建的验收要求。下载时必须核对对应产物的元数据；未提供元数据或仍处于待验证状态的产物，不应视为已满足目标。

## 构建

### GitHub Actions

在 Actions 中运行 **Build Windows 11 Pro 26H2 ARM64 for DroidVM**。关键输入如下；更新包地址、SHA256 和精确目标版本由 `windows/updates.json` 固定。

| 输入 | 建议值 / 含义 |
|---|---|
| `iso_lang` / `dvm_locale` | `Chinese (Simplified)` / `zh-CN`；语言设置应当与 ISO 一致 |
| `win_release` | `26H2`；ISO 的原始构建号不等于更新后的目标构建号 |
| `image_index` | `0` 自动选择 Pro ARM64；指定索引也必须通过版本与架构校验 |
| `runner` | `windows-2022` 或有足够空间的 Windows runner；以预检结果为准 |
| `debloat_level` / `keep_cjk` | `standard` / `true`，保留中文字体、输入法及语言资源 |
| `ems_sac` | 无网络测试可选 `skip`；`online` 需要来宾首次启动时联网获取交互式 SAC 组件 |
| `publish_release` | 是否发布分片；发布不等于手机启动验证 |

工作流通过 [Fido](https://github.com/pbatard/Fido)解析微软官方下载地址。必须检查 ISO、官方更新包与最终镜像的实际信息，不应把“下载当前 ISO”当作达到 `26300.9550` 的保证。

### 本地 x64 Windows

需要管理员权限、bcdboot / diskpart、支持 26H2 的 Windows ADK 部署工具或对应新版系统 DISM，以及 `qemu-img`。工作流会安装微软 ADK 部署工具。准备官方 ARM64 ISO，并预留足够空间供 ISO、更新包、VHDX、转换输出及 ESD 导出使用；KB5124010 包由脚本下载并校验。

设置官方 ISO 路径，并按需编辑 `windows_build.ps1` 的账户和输出配置，在仓库目录运行：

```powershell
$env:SRC_ISO = 'E:\ISO\Windows11_Client_arm64_zh-cn_26300_9457.iso'
# 使用 ADK 时，设置其 amd64 DISM 目录；脚本会导入对应 Dism 模块
$env:DVM_DISM_DIR = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\DISM'
powershell -ExecutionPolicy Bypass -File .\windows_build.ps1
```

入口脚本会设置自己的环境变量，不能假定在外部设置的同名值会保留。主要配置包括 `SRC_ISO`、`DRIVERS_DIR`、`DRIVER_INSTALL`、`DRIVER_CERT`、`OUT_QCOW`、`OUT_VMPKG`、`DVM_USERNAME` 和 `DVM_PASSWORD`；新 Pro 构建还必须满足上表的目标和更新要求。

[windows/README.md](windows/README.md)保留上游离线构建、驱动和 EMS/SAC 细节，其中的体积、默认配置及功能描述不代表本分支的实测承诺。`macos_build.sh` 和 [macos/](macos/)是保留的上游实验路径，**本分支未验证其中文、Pro 选择、KB5124010 更新或与 Windows 路径的产物等价性**。

## 中文保留与精简

简体中文应当使用官方 zh-CN ISO，并设置 `DROIDVM_LOCALE=zh-CN`、`DROIDVM_KEEP_CJK=1`。中文保留策略保护 CJK 字体、IME、`InputMethod\CHS` / `CHT` 和语言功能；这不等于所有应用和输入功能均已实测。

| 级别 | 行为 |
|---|---|
| `standard` | 按维护的列表移除应用，建议作为起点 |
| `minimal` | 进一步移除未受保护的预配应用，必须检查所需功能是否保留 |
| `off` | 关闭 tiny11 风格应用精简；本地构建还应设置 `DROIDVM_DEBLOAT=0` |

这些级别不承诺关闭其他镜像配置步骤。精简模块保留组件存储，不采用 tiny11 Core 的组件存储删除方式；首次登录脚本另有服务调整，可能关闭 Windows Update，桌面提供 `enable_windows_update.bat`。组件存在与更新服务已启用是两件事。

## 下载、校验与导入

构建输出包括 `.qcow2` 和 `.vmpkg`。发布时按 **1900 MiB** 分片，并提供各原始文件的 SHA256 清单；总大小取决于实际镜像和压缩设置，不提供固定体积承诺。

下载一种产物的全部 `.partNN` 和对应 `.sha256` 到独立目录。**不能把 qcow2 与 vmpkg 分片混放**：`join-files.ps1` 会拼接目录中所有匹配的分片，并读取其中的 SHA256 文件。合并目标文件会被覆盖。

```powershell
# 在仓库目录执行；每个目录只放一种产物及其 SHA256 清单
powershell -ExecutionPolicy Bypass -File .\scripts\join-files.ps1 `
  -PartsDir .\parts-vmpkg -OutFile .\win11-arm64-droidvm.vmpkg

# 仅在需要裸磁盘时合并 qcow2
powershell -ExecutionPolicy Bypass -File .\scripts\join-files.ps1 `
  -PartsDir .\parts-qcow2 -OutFile .\win11-arm64-droidvm.qcow2
```

必须看到 `sha256 OK` 才视为通过完整文件校验；缺少 `.sha256` 时脚本仍可合并，但不能据此声称已校验。校验通过后，在 DroidVM 中导入 `.vmpkg`；裸 `.qcow2` 需要另外配置虚拟机。首次硬件识别和系统配置发生在目标手机上，离线构建不会替代启动测试。

## 手机配置与安全

- [K70 Pro 验证记录](docs/k70pro.md)给出已启动的 Pro 26H2 / `26300.9550` 环境及历史家庭版选择问题。首次初始化经过“准备就绪”后曾黑屏，停止并重新启动虚拟机后进入桌面；手机没有重启。不能把成功归因于未经独立对照的某个参数。
- 网络是可选功能，未在该手机验证中测试；当前目标模板不配置网络。RDP 服务端需要 Pro，Home 启动成功不代表 RDP 可用；SSH、网桥和联网 SAC 也不能视为已验证。
- 默认管理员账户为 `USER`，默认密码为 `DroidVM`。**必须在接入任何网络之前更换密码**，并检查自动登录、远程服务和防火墙设置。
- 驱动证书、`testsigning` 和 `nointegritychecks` 用于测试签名驱动的信任与加载，会影响安全边界；它们不是 Windows 激活机制。Windows 授权与激活必须通过合法方式处理，本项目不提供盗版激活工具。
- 本构建器只处理来宾镜像，**不包含手机 CPU / 固件刷写或宿主内核部署**。宿主修复与 DroidVM 版本是外部前提，必须另行评估。
