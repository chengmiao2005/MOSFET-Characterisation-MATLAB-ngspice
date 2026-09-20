# MATLAB 与 ngspice MOSFET 表征项目

**基于仿真的器件建模、参数提取与测量误差分析。**

[English](README.md) · [详细结果](docs/RESULTS.md) · [公开版本整理记录](PUBLICATION_NOTES.md)

本项目研究三个问题：怎样用模型生成 MOSFET 电流曲线、读数误差会怎样影响阈值估计，以及需要什么扫描数据才能确定器件模型参数。内容包含 MATLAB 模型、实际执行的 ngspice 扫描、参数提取、留出点检查和 Python 数值复核。

**所有数据均为模型仿真或合成读数，没有真实器件实测。**

## 主要成果

| 内容 | 已完成结果 |
|---|---|
| 读数误差分析 | 保存 400 组配对场景，比较单次读数、25 次平均及校准的影响 |
| 校准与平均 | 当前假设下，阈值 RMSE 从未校准平均的 **12.543 mV** 降至校准后平均的 **0.901 mV** |
| MATLAB–SPICE 对照 | **8 组 DC 曲线、1,078 条记录**均满足原定容差 |
| 三参数提取 | 提取结果约为 **Vth = 1.200 V、β = 0.002000 A/V²、λ = 0.02000 V⁻¹** |
| 留出点检查 | **107 个不同拟合偏置点、959 个不同留出偏置点**，两组无重叠 |
| 参数可辨识性 | 解释为什么一条固定漏压转移曲线不能分别确定 β 和 λ，以及输出扫描如何补充信息 |

![400 组合成场景的阈值 RMSE 比较](summary_figures/synthetic_calibration_rmse.png)

平均主要降低随机波动，校准则估计并修正增益和零点偏差。总体改善不代表每次都改善：**400 组中仍有 15 组在校准后平均时，阈值绝对误差更大**，这些结果已完整保留。

![输出扫描区分共享同一转移曲线的参数组合](summary_figures/output_identifiability.png)

在本模型的饱和区，固定漏源电压 VDS 后，转移曲线约束的是 **β(1 + λVDS)**。多组 β 和 λ 可以让这个组合不变，因此曲线重合；增加漏压扫描，才获得区分它们的信息。把原来一条曲线扫得更密，不能替代这种额外信息。

## 三个阶段

| 阶段 | 做什么 | 入口 |
|---|---|---|
| Stage 1 | 加入增益、零点、噪声与量化误差；比较平均和两点校准 | [`PSI_MOSFET_Stage1.m`](project/stage1/PSI_MOSFET_Stage1.m) |
| Stage 2 | 分离误差机制、演示错误拟合区域，再实际调用 ngspice 对照 | [`RUN_STAGE2B.m`](project/stage2/RUN_STAGE2B.m) |
| Stage 3 | 反推 Vth、β、λ；排除重复偏置点；检查未参与拟合的数据 | [`RUN_STAGE3.m`](project/stage3/RUN_STAGE3.m) |

## 怎么运行

归档成功记录使用 **MATLAB R2024a + ngspice 47**。程序使用基础 MATLAB，不依赖 Simulink 或优化工具箱；其他 MATLAB 版本的兼容性尚未在此确认。ngspice 需通过[官网下载](https://ngspice.sourceforge.io/download.html)，本仓库不包含引擎程序。

**最快体验：运行 Stage 3。** 将 MATLAB 当前文件夹切换到 `project/stage3`，输入：

```matlab
RUN_STAGE3
```

这一步读取仓库已经附带的成功 SPICE 数据，生成新的 `outputs_stage3/` 结果和 ZIP，不会再次调用 ngspice，也不会自动读取新跑的 Stage 2 结果。

需要重新运行前两阶段时，分别切换当前文件夹，再执行对应命令：

```matlab
% 当前文件夹：project/stage1
PSI_MOSFET_Stage1

% 当前文件夹：project/stage2
RUN_STAGE2B
```

Stage 2B 弹窗中选择完整 ngspice 安装目录里的可执行程序；Windows 通常选择 `ngspice_con.exe`。取消选择会停止。不要用不带参数的 `PSI_MOSFET_Stage2` 代替完整入口，它只会执行 2A。

## 已核验的范围

归档 MATLAB 自检为 Stage 1 **12/12**、Stage 2A **9/9**、Stage 3 **13/13**。针对当前公开数据重新运行的 Python 审核为 Stage 2 **63/63**、Stage 3 **21/21**。Python 只复算归档数据，不代表重新执行 MATLAB/ngspice。运行命令见[英文说明](README.md#recheck-the-archived-numerical-results-with-python)。

留出点电流 RMSE 约 **3.732 pA**、最大绝对残差约 **11.623 pA**，反映同一已知模型下的数值一致性，**不能写成测量仪器的精度**。拟合窗口由模型知识选定；当前结果也不能替代真实器件验证、物理校准溯源或模型失配研究。

代码在 [`project/`](project/)，完整运行记录在 [`evidence/`](evidence/)，独立实现的数值检查在 [`verification/`](verification/)。更完整的参数小数、数据划分和公式见[详细结果](docs/RESULTS.md)。
