# Cloud GPU 复现工作记录

## 背景

本地 WSL2 + RTX 5060 Laptop (8GB VRAM) 无法运行 habitat-sim GPU 渲染（WSL2 不提供 NVIDIA EGL ICD），因此租用云 GPU 服务器进行评估。

---

## 第一台服务器：RTX 3090 24GB

- **平台**：非 AutoDL 平台
- **配置**：RTX 3090 24GB, 30GB 系统盘, 50GB 数据盘
- **基础镜像**：PyTorch 2.5.1 + CUDA 12.4 + Python 3.12
- **使用时间**：2026-04-06 ~ 2026-04-07

### 环境搭建过程

#### 1. Conda 环境 (Python 3.9)
```bash
conda create -n janusvln python=3.9 -y
```
需要 Python 3.9 因为 habitat-sim 0.2.4 仅支持 Python ≤3.9。在 Python 3.12 基础镜像上创建 3.9 conda 环境即可。

#### 2. habitat-sim 0.2.4
```bash
conda install -n janusvln habitat-sim=0.2.4 withbullet headless -c conda-forge -c aihabitat -y
```
安装顺利，headless 模式使用 EGL 后端渲染（无需显示器）。

#### 3. habitat-lab + habitat-baselines 0.2.4
```bash
# 中国网络需要 GitHub 代理
pip install "git+https://ghfast.top/https://github.com/facebookresearch/habitat-lab.git@v0.2.4#subdirectory=habitat-lab"
pip install "git+https://ghfast.top/https://github.com/facebookresearch/habitat-lab.git@v0.2.4#subdirectory=habitat-baselines"
```
**问题**：直接从 github.com clone 在中国极慢（20+分钟无响应）。  
**解决**：使用 `ghfast.top` 代理加速。

#### 4. PyTorch 2.5.1
基础镜像自带，或：
```bash
pip install torch==2.5.1 torchvision==0.20.1 --index-url https://download.pytorch.org/whl/cu124
```

#### 5. flash-attn 2.7.4（最耗时的一步）
多次尝试失败：

| 尝试 | 方式 | 结果 |
|------|------|------|
| 1 | `pip install flash-attn`（阿里云镜像） | 无预编译 wheel，从源码编译，下载 cutlass 卡住 |
| 2 | `pip install flash-attn`（PyPI） | 国际网络太慢 |
| 3 | 源码编译 | 下载依赖卡住 |
| 4 | 改用 `sdpa` attention | 不兼容：视觉编码器使用 `cu_seqlens` 参数，仅 flash-attn 支持 |
| 5 | **GitHub 预编译 wheel + ghfast 代理** ✅ | 成功！ |

**最终解决方案**：
```bash
pip install https://ghfast.top/https://github.com/Dao-AILab/flash-attention/releases/download/v2.7.4.post1/flash_attn-2.7.4.post1+cu12torch2.5cxx11abiFALSE-cp39-cp39-linux_x86_64.whl
```
通过 ghfast 代理从 GitHub Releases 下载预编译 wheel，187MB 约 33 秒完成。

**关键教训**：`sdpa`（PyTorch 内置 scaled_dot_product_attention）不能替代 flash-attn，因为 Qwen2.5-VL 的视觉编码器在 attention 计算中使用了 `cu_seqlens`（可变长度序列拼接），这是 flash-attn 的专有功能。

#### 6. 其他依赖
```bash
pip install fastdtw networkx "tensorboard>=2.16" bitsandbytes
```
- `fastdtw`：评估代码用到但不在 requirements.txt 中
- `tensorboard>=2.16`：旧版与 NumPy 2.x 不兼容（`np.bool8` 被移除）

### 数据准备

#### 模型权重（ModelScope，国内 CDN）
```bash
pip install modelscope
modelscope download --model misstl/JanusVLN_Extra --local_dir /root/data/models/JanusVLN_Extra
```
4 个 safetensors 文件，共 ~18GB。ModelScope 国内下载速度快。

#### R2R VLN-CE Episodes
从本机 scp 传输，约 251MB。包含 val_unseen、val_seen、test、train 分割。

#### MP3D 场景（11 个 val_unseen 场景）
从本机 scp 传输，约 663MB。场景列表：
```
2azQ1b91cZZ, 8194nk5LbLH, EU6Fwq7SyZv, QUCTc6BB5sX, TbHJrupSAjP,
X7HyMhZNoso, Z6MFQCViBuw, oLBMNvg9in8, pLe4wQe7qrG, x8F5xyUWy9e, zsNo4HB9uLZ
```

#### 磁盘空间管理
**问题**：30GB 系统盘装完 conda + 依赖后只剩几 GB。  
**解决**：模型权重放数据盘 `/root/data/`，通过符号链接映射：
```bash
ln -s /root/data/models /root/JanusVLN/models
```

### 评估尝试与显存分析

#### 尝试 1：bf16 全精度（无量化）
```bash
torchrun --nproc_per_node=1 src/evaluation.py --model_path models/JanusVLN_Extra \
  --habitat_config_path config/vln_r2r.yaml --eval_split val_unseen --output_path evaluation
```
**结果**：OOM。模型加载成功，Habitat 初始化成功，第一个 episode 推理时在 `lm_head` 处崩溃。
```
torch.OutOfMemoryError: Tried to allocate 1.04 GiB. GPU has 23.56 GiB total, 834.75 MiB free.
PyTorch allocated: 20.27 GiB
```

#### 尝试 2：bf16 无视频（去掉 --save_video）
**结果**：同样 OOM。去掉视频保存对显存几乎无影响。
```
PyTorch allocated: 21.45 GiB, free: 944.75 MiB
```

#### 尝试 3：4-bit NF4 量化 + device_map="auto"
应用 evaluation_quantize.patch，使用 BitsAndBytesConfig 4-bit 量化。
**结果**：`ValueError: Pointer argument (at 0) cannot be accessed from Triton (cpu tensor?)`  
**原因**：`device_map="auto"` 将部分层放到 CPU，flash-attn 的 Triton kernel 不能处理 CPU tensor。

#### 尝试 4：4-bit 量化 + device_map 单 GPU
改为 `device_map={"": device}` 强制全部放 GPU。
**结果**：OOM，PyTorch 占用 22GB。  
**原因**：bitsandbytes 只量化 `nn.Linear`，VGGT (~2GB)、Conv2d、Embedding、LayerNorm 都保持 bf16。

#### 尝试 5：4-bit + eager attention + device_map="auto"
改用 eager attention（不依赖 Triton）以兼容 CPU offload。
**结果**：`AssertionError: module.weight.shape[1] == 1`  
**原因**：bnb 4-bit 的 `Linear4bit` 与 VGGT 内部的 DINOv2 ViT 自定义 attention 不兼容。

#### 尝试 6：8-bit INT8 量化
使用 `load_in_8bit=True`。
**结果**：`AttributeError: 'Parameter' object has no attribute 'CB'`  
**原因**：bnb 8-bit 的 `Linear8bitLt` 与视觉投影层（自定义 MLP）不兼容。

#### 尝试 7：8-bit + llm_int8_skip_modules
跳过 VGGT 和视觉相关模块的量化。
**结果**：模型加载成功（13.4GB），但推理时 OOM。  
**原因**：未量化的 VGGT + 推理时的 KV cache/激活值仍超 24GB。

### 显存占用分析

| 组件 | bf16 | 8-bit (LLM only) | 4-bit (LLM only) |
|------|------|-------------------|-------------------|
| LLM Linear 层 | ~10GB | ~5GB | ~3GB |
| VGGT (1B, 不可量化) | ~2GB | ~2GB | ~2GB |
| 视觉编码器 (Conv2d等) | ~2GB | ~2GB | ~2GB |
| lm_head + Embedding | ~0.5GB | ~0.5GB | ~0.5GB |
| **模型权重小计** | **~14.5GB** | **~9.5GB** | **~7.5GB** |
| KV cache + 推理激活值 | ~7-8GB | ~7-8GB | ~7-8GB |
| Habitat-sim 渲染 | ~1.2GB | ~1.2GB | ~1.2GB |
| **推理峰值总计** | **~23GB** | **~18GB** | **~16GB** |
| 3090 24GB 能跑？ | ❌ OOM | ❌ bnb不兼容 | ❌ bnb不兼容 |

### 核心结论

**RTX 3090 24GB 无法运行 JanusVLN 评估，原因有两个：**

1. **显存不足**：bf16 全精度推理峰值 ~23GB，3090 的 24GB 没有余量，在推理过程中 OOM。
2. **量化不兼容**：JanusVLN 是 Qwen2.5-VL-7B + VGGT-1B 的混合架构，VGGT 使用自定义 DINOv2 ViT，其 attention 层和 Linear 层与 bitsandbytes 的量化机制（Linear4bit/Linear8bitLt）不兼容。无法通过量化来减少显存。

**最低显存需求：40GB**（bf16 全精度 ~23GB + 安全余量）。

### VGGT 与 bitsandbytes 不兼容的技术细节

bitsandbytes 量化替换所有 `nn.Linear` 为 `Linear4bit` 或 `Linear8bitLt`。但 VGGT 的 DINOv2 ViT 中：
- 自定义的 `Block` 和 `MemEffAttention` 层直接操作权重 tensor
- 8-bit 模式下访问 `weight.CB` 属性（量化后的权重没有此属性引发 AttributeError）
- 4-bit 模式下 `fix_4bit_weight_quant_state_from_module` 断言失败
- 使用 `llm_int8_skip_modules` 可以跳过 VGGT，但剩余未量化的权重 + 推理开销仍超 24GB

### 附加发现

#### WSL2 不支持 habitat-sim GPU 渲染
```
RuntimeError: unable to find CUDA device 0 among 1 EGL devices in total
```
WSL2 提供 CUDA 计算但不提供 NVIDIA EGL ICD，habitat-sim 无法做 GPU 渲染。尝试安装 `libnvidia-gl`（版本不匹配 segfault）、Mesa EGL、WSLg 等均失败。必须使用原生 Linux 或云 GPU。

#### 中国网络环境优化
| 资源 | 加速方式 |
|------|---------|
| pip 包 | 阿里云镜像 `mirrors.aliyun.com/pypi/simple/` |
| GitHub clone/下载 | `ghfast.top` 代理 |
| 模型权重 | ModelScope 国内 CDN |
| flash-attn | GitHub Releases 预编译 wheel + ghfast 代理 |

---

## 第二台服务器：A100 PCIe 40GB ✅

- **平台**：AutoDL
- **配置**：A100 PCIe 40GB, 30GB 系统盘, 50GB 数据盘
- **基础镜像**：PyTorch 2.5.1 + CUDA 12.4 + Python 3.12
- **费用**：3 CNY/hour
- **使用时间**：2026-04-07

### 环境搭建（约 30 分钟）

复用 3090 上验证的安装流程，无卡模式下完成所有准备：

1. `conda create -n janusvln python=3.9` — conda 环境
2. `conda install habitat-sim=0.2.4 withbullet headless` — 模拟器
3. `pip install torch==2.5.1 torchvision==0.20.1 --index-url .../cu124` — PyTorch
4. `pip install git+https://ghfast.top/.../habitat-lab.git@v0.2.4` — habitat-lab + baselines
5. `pip install https://ghfast.top/.../flash_attn-2.7.4.post1+cu12torch2.5...whl` — flash-attn
6. `pip install transformers==4.50.0 accelerate fastdtw qwen-vl-utils ...` — 其他依赖
7. `apt install libegl1-mesa-dev` — EGL 渲染库（GPU 模式需要）
8. `modelscope download --model misstl/JanusVLN_Extra` — 模型权重（国内 CDN）
9. 本机 scp 传输 MP3D 场景 + R2R episodes

### 遇到的问题

| 问题 | 解决 |
|------|------|
| `libEGL.so.1` not found | `apt install libegl1-mesa-dev` |
| `No module named 'qwen_vl_utils'` | `pip install qwen-vl-utils` |
| MP3D 传输为断裂 symlink | tar 时从实际路径打包，非 symlink 路径 |

### 评估运行

bf16 全精度，无需量化。GPU 峰值占用 27.3GB / 40GB。

```bash
torchrun --nproc_per_node=1 src/evaluation.py \
  --model_path models/JanusVLN_Extra \
  --habitat_config_path config/vln_r2r.yaml \
  --eval_split val_unseen_30 \
  --output_path evaluation_30 \
  --save_video --save_video_ratio 1.0
```

30 个 episode（每场景 3 个，10 个场景），全部保存视频，总耗时约 68 分钟。

### 结果

| 指标 | 论文 (Extra, 1839 ep) | 论文 (Base, 1839 ep) | 我们 (30 ep) |
|------|---------------------|---------------------|-------------|
| SR   | 60.5%               | 52.8%               | **53.3%**   |
| SPL  | 56.8%               | 49.2%               | **41.1%**   |
| OS   | 65.2%               | 58.0%               | **66.7%**   |
| NE   | 4.78m               | 5.17m               | **5.42m**   |

结果与论文基本一致，差异来自 30 episode 的小样本方差。复现成功。

---

## 文件变更记录

### 在 3090 上修改过的文件（未入库）

#### `src/evaluation.py`（在 3090 服务器上直接修改）
1. 应用 `evaluation_quantize.patch`（添加 `--quantize_4bit` 支持）
2. 添加 `--quantize_8bit` 参数和 8-bit 量化逻辑
3. 添加 `llm_int8_skip_modules` 跳过 VGGT
4. 多次切换 `device_map`（"auto" vs 单GPU）和 `attn_implementation`（flash_attention_2 vs eager）

#### `src/qwen_vl/model/vggt/models/aggregator.py`（在 3090 服务器上直接修改）
添加 dtype 转换修复（line 227-230）：
```python
target_dtype = next(self.patch_embed.parameters()).dtype
if images.dtype != target_dtype:
    images = images.to(target_dtype)
```
此修复对量化模式是必要的，但在 40GB+ GPU 上用 bf16 全精度时不需要。

### 本地仓库文件
所有复现基础设施文件（Dockerfile、scripts、patches 等）均在本地仓库中管理，通过 git 追踪。详见 `REPRODUCTION.md`。
