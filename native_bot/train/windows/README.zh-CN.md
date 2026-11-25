# Windows 三麻模型训练指南

本指南使用 Akagi 自带的三麻特征、动作空间和牌谱提取器，在 Windows + NVIDIA GPU 上训练候选模型。训练产物与 Akagi 内置推理保持一致，不需要把 Meowjong 的模型格式移植进来。

> **重要：** 训练、评估和使用 AI 的方式必须遵守你所玩平台的服务条款。本流程用于本地研究、牌谱分析和获准的测试环境。

## 1. Windows 环境

建议使用 64 位 Windows 10/11、NVIDIA RTX 5090 Laptop、至少 32 GB 系统内存和足够的 SSD 空间。400 万样本的三麻提取数据约数 GB，训练脚本会将数据读入内存。

安装以下工具：

- NVIDIA 显卡驱动。
- Python 3.11 或 3.12，并在安装器中启用 `py` launcher。
- Rust stable 和 Visual Studio Build Tools 的 **Desktop development with C++** 工作负载（MSVC）。
- Git（可选，用于下载牌谱或更新代码）。

在 PowerShell 中进入 Akagi 仓库，然后安装 CUDA 版 PyTorch 和训练依赖：

```powershell
cd native_bot\train\windows
.\setup.ps1
```

脚本创建 `native_bot/train/.venv`，安装 PyTorch CUDA 12.8 wheel、NumPy 和 safetensors，并检查 `torch.cuda.is_available()`。若显卡不可用，脚本会报错退出，不会默默转到 CPU。

如果后续 PyTorch 官网为当前版本推荐不同 CUDA wheel，请以 [PyTorch 安装选择器](https://pytorch.org/get-started/locally/)为准，并确保使用支持 Blackwell 显卡的 CUDA 构建。

## 2. 准备牌谱

提取器输入是 Akagi 使用的 MJAI JSON 游戏日志，每局一个 `.json.gz` 文件，可递归放在目录下。训练和验证数据必须来自**互不重叠的完整牌局**；推荐按日期或牌谱 ID 划分目录。项目不会替你下载或再分发牌谱，请自行准备并遵守数据来源的使用条款。

目录示例：

```text
D:\sanma-data\
  train\2025-01\*.json.gz
  validation\2025-02\*.json.gz
```

## 3. 提取三麻样本

回到仓库根目录后运行以下命令；路径也可以改成绝对路径：

```powershell
.\native_bot\train\windows\extract_sanma.ps1 `
  -Dataset D:\sanma-data\train `
  -Output native_bot\out\sanma-train `
  -MaxGames 40000 `
  -MaxSamples 4000000

.\native_bot\train\windows\extract_sanma.ps1 `
  -Dataset D:\sanma-data\validation `
  -Output native_bot\out\sanma-validation `
  -MaxGames 5000 `
  -MaxSamples 500000
```

脚本会编译 Rust 提取器，并检查输入目录含有 `.gz` 文件。输出目录必须是新目录，避免意外覆盖已有样本。提取器会跳过无法回放的牌谱；请检查命令输出中的游戏数和样本数。

## 4. 训练候选模型

```powershell
.\native_bot\train\windows\train_sanma.ps1 `
  -Dataset native_bot\out\sanma-train `
  -ValidationDataset native_bot\out\sanma-validation `
  -Output native_bot\out\models\akagi3p-candidate.safetensors `
  -Epochs 10 `
  -BatchSize 2048
```

训练脚本会强制使用 CUDA。模型架构与 Akagi 当前 Rust 推理端一致：37 个特征通道、27 种三麻牌种、60 个动作。首轮应保持架构不变，先验证数据质量、合法动作遮罩和对局强度；`val_top1` 只是牌谱动作预测准确率，不能单独代表实战棋力。

若暂时没有独立验证集，可省略 `-ValidationDataset`。此时训练器使用随机样本切分，指标可能因为相邻决策泄漏而偏乐观，不应作为模型晋级依据。

## 5. 验证候选权重与 Rust 推理一致

```powershell
.\native_bot\train\windows\verify_candidate.ps1 `
  -Model native_bot\out\models\akagi3p-candidate.safetensors
```

该检查生成确定性输入，验证 PyTorch 导出的 safetensors 能被 Rust/Candle 加载，且 logits 与 PyTorch 的差异小于 `2e-3`、argmax 一致。它不会覆盖当前内置权重。

## 6. 对局评测与接入

先通过 Akagi 的 MJAI 外部 bot 接口进行合法动作、规则和计时测试，再用旧模型作对照，以相同牌山/随机种子、多座位进行大量对局。记录平均顺位、点数变化和置信区间；候选模型未稳定胜过基线前，不要替换内置权重。

当前 Akagi 内置权重通过 `include_bytes!` 编译进程序。要临时本地试用候选模型，应先备份 `native_bot/weights/akagi3p.safetensors`，将候选文件复制到该路径，再构建 Akagi；正式集成前要保留原始权重以便回滚。不要把牌谱、提取 shard、个人训练 checkpoint 或本地游戏记录提交到 GitHub。

## 7. 常见问题

- **CUDA 不可用：**更新 NVIDIA 驱动，确认安装的是 CUDA 版 PyTorch；重新运行 `.\setup.ps1` 检查。
- **`cargo` / linker 不可用：**安装 Rust MSVC 工具链和 Visual Studio C++ Build Tools 后重新打开 PowerShell。
- **内存不足：**降低样本上限或训练 batch；训练脚本目前会把每个数据集载入主机内存。
- **验证分数很好但实战没提升：**使用按整局/日期隔离的 validation 数据，并以多种子对战评测为准。
- **候选模型加载失败：**确认是本项目的训练脚本导出的三麻 safetensors；不要将 Mortal/Meowjong checkpoint 直接重命名为 Akagi 权重。
