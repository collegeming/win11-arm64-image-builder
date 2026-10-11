# Windows 11 Pro 26H2 镜像体积分析与缩减结果

## 结论

2026-10-11 的实测表明，专业版镜像看起来大幅增大，首先是两次构建的压缩参数不同：历史家庭版开启 QCOW2 内部 zstd 压缩，专业版构建关闭了内部压缩。KB5124010 和专业版的系统内容也与旧镜像不同，但没有仅改变 KB 的单变量构建，不能把全部增量算作补丁残留。

不删除任何 Windows 文件的无损压缩已将本地专业版原始磁盘从 **22.65 GiB 降至 11.52 GiB，减少 49.11%**。手机已初始化磁盘也从 **23.33 GiB 降至 11.55 GiB**，压缩前后 guest 可见扇区比较完全一致。手机压缩副本已实际进入中文桌面。

## 可比较的大小

| 对象 | 字节数 | 条件 |
|---|---:|---|
| 历史 Home 构建 QCOW2 | 8,393,719,808 | 内部 zstd；26300.9457 |
| 历史 Home VMPKG | 8,393,740,288 | 外层不压缩；内容为上述 zstd 磁盘 |
| Pro + KB5124010 原始 QCOW2 | 24,315,363,328 | 内部未压缩；26300.9550 |
| Pro 原始 VMPKG | 11,686,834,176 | 外层 gzip |
| Pro 无损内部 zstd QCOW2 | 12,373,721,088 | guest 扇区与原始 Pro 完全一致 |
| Pro 外层 zstd VMPKG | 11,205,156,864 | 内含原始未压缩 Pro；约 10.44 GiB |
| 手机初始化后 Pro，压缩前 | 25,045,565,440 | 已运行和写入的磁盘 |
| 同一手机磁盘刚完成内部 zstd 压缩 | 12,398,166,016 | 比较通过后才启动；启动后会继续增长 |

内部压缩省的是手机存储；外层封装压缩省的是下载量，解包后的磁盘大小不变。外层 zstd 相比已有 gzip 包只减少约 **459 MiB（4.12%）**。同一个磁盘使用不同压缩层，不能把两种收益叠加计算。

手机原始文件和历史备份保留，当前压缩副本启动、清理和写入后为 13,118,799,872 字节（约 12.22 GiB）。这是写入会使压缩簇转为未压缩簇的正常变化。因为备份未删除，手机整体已用空间不会立即净减少；删除备份属于独立操作，不包含在本次处理里。

## 补丁残留与 Windows 实际占用

构建日志表明，KB5124010 后的离线 `StartComponentCleanup /ResetBase` 和 ReTrim 都成功，Appx 精简 removed=22、kept=23、failed=0。没有“精简模块没执行”的证据。更新下载包留在构建主机缓存目录，不是简单复制到来宾 C 盘。

只读检查原始 Pro 镜像：NTFS 已用约 16 GiB，QCOW2 却占约 22.65 GiB，说明已分配的磁盘簇与现存文件占用不是同一个量。已删除文件留下的非零数据不能仅凭文件系统显示空闲而由普通 qemu-img 压缩自动识别。

启动后的 Windows DISM 官方组件分析显示：

| 指标 | 清理前 / 清理后观察 |
|---|---|
| 组件存储实际大小 | 12.81 GB / 12.81 GB |
| 与 Windows 共享部分 | 9.28 GB / 9.28 GB |
| 备份与已禁用功能 | 3.52 GB / 3.52 GB |
| 缓存和临时数据 | 0 字节 / 0 字节 |
| 可回收包数 | 2 / 2 |

随后执行了不带 `/ResetBase` 的在线 `StartComponentCleanup`，命令成功，但没有观察到组件大小或可回收包数下降。因此不能宣称又释放了 3.52 GB；其中“备份与已禁用功能”也不等于全部可删垃圾。未继续强制 ResetBase 或手工删除 WinSxS。

常见残留检查：

- `SoftwareDistribution\Download` 与 `CbsTemp` 未找到缓存文件；不是几个 GiB 的补丁下载残留。
- `Windows\Temp` 测量仅 622 字节。
- 使用正确字面路径检查 `$WinREAgent`、`Windows.old`、`hiberfil.sys`，未找到对应条目。先前一个错误引号命令把 `$WinREAgent` 展开成 C 盘根目录，其统计已排除，不作为证据。
- `pagefile.sys` 分配为 1216 MiB。来宾内存仅 1792 MiB，保留系统管理的分页文件，避免为省空间提高内存不足风险。

## 保守处理与未采用方案

### 已完成

1. 本地与手机磁盘分别创建新压缩副本，不覆盖原文件。
2. 执行 `qemu-img check`，无结构错误；`qemu-img compare` 通过，guest 可见数据完全一致。
3. 手机压缩副本通过 VNC 实际进入中文桌面；没有仅把 CLI 的 running 当作启动证据。
4. 外层 zstd VMPKG 流式解包计算嵌入磁盘 SHA256，匹配原始 Pro 磁盘。
5. 原 Windows11 条目已指向压缩磁盘，恢复单条配置；临时验证 VM 已停止。手机屏幕处于锁屏，正式条目目前为 STOPPED，需在 App 内点击启动，不绕过锁屏。
6. 本地工作区调整工作流内部 zstd 默认值、优先使用 Windows 原生 tar，并增加组件清理前后分析日志。未重新构建或发布这些本地代码调整。

### 未采用

- 不删除 WinSxS、驱动、中文字体、IME、组件存储或现用 KB 文件。
- Windows `CompactOS:query` 显示当前未压缩，并由系统判断不适用；没有强制开启。CompactOS 可逆但增加 CPU 解压工作，与 QCOW2 压缩叠加后的性能未测，不作为当前默认。
- NTFS 空闲区清零仅进行了 disposable overlay 上的 dry-run；工具出现 inode 读取错误，已断开，没有执行写入，也没有将该实验作为有效优化。
- 不缩小 40 GiB 虚拟容量。文件体积与虚拟磁盘容量是不同概念。
- 原始镜像、下载包及备份仍保留。它们不是 Windows 系统内部补丁残留，清理前必须区分当前使用的文件、可回退备份和可重新下载的附件。

## 文件与校验

- 内部 zstd 原始 Pro QCOW2：`win11-pro-26h2-26300.9550-arm64-zstd.qcow2`，SHA256 `9bd56de151f0f77c9dd63eee7ae0ec3b2e3366ceaac33b77220f5fa3f3039bd3`。
- 外层 zstd 下载包：`win11-pro-26h2-26300.9550-download-zstd.vmpkg`，内嵌磁盘 SHA256 与原始 Pro 相同：`a5a3770849dfe50960ae43864bdb1fe56cf7ca97fd9fd1a9fcb8073ca4584300`。
- 手机当前配置磁盘：`/storage/emulated/0/DroidVM/win11-pro-26h2-26300.9550-arm64-compact.qcow2`。该文件已完成首启与后续清理，不是发布前原始镜像。

外层 zstd 包的 tar 大文件大小使用 base-256，需支持该格式的 DroidVM 开发版；不能宣称旧版 App 均兼容。现有 GitHub Release 附件没有替换，仍对应原发布 SHA256。

## 依据

本次使用 Exa 检索 30 条结果，优先核对微软和 QEMU 官方资料；项目结论以实际构建日志、文件测量和设备输出为准。

- [Microsoft：清理 WinSxS 的支持方法与手工删除风险](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/clean-up-the-winsxs-folder?view=windows-11)
- [Microsoft：离线组件存储清理](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/reduce-the-size-of-the-component-store-in-an-offline-windows-image?view=windows-11)
- [Microsoft：CompactOS](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/compact-os?view=windows-11)
- [QEMU：convert / compare / 压缩簇](https://www.qemu.org/docs/master/tools/qemu-img.html)
