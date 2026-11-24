# cann-shmem MTE atomic probe (F1)

验 cann-shmem 的 MTE 原子面在 910C 上到底成不成立（followups 文档 F1）。
判据来自 F1 原文：**单 PE 内两核并发累加终值正确 + 跨 PE 两 rank 的
atomic_add 终值正确**，另验 `aclshmemx_signal_op(ADD)` 并发累加。

## 用例

| case | 内容 | 期望终值 |
|---|---|---|
| `add_u32/u64/i32/f32` | 每个 PE 对 PE0 同一字 add 1，各 iters 次 | iters × npes |
| `cas_u32/u64/i32/f32` | 每个 PE 对 PE0 同一字 CAS 自增（返回旧值驱动循环） | iters × npes |
| `sig_add` | 每个 PE 对 PE0 同一 int32 字 signal ADD 1，各 iters 次 | iters × npes |
| `intra2_u32` | 同一 PE 的 2 个 AIV core 对本地字各 add iters 次（u32 路径已知不累加，只作对照） | iters × 2 |
| `intra2_i32` | 同上，int32（累加路径，回答 F1 的双核判据） | iters × 2 |

内核只发操作不轮询，宿主等终值（20 s 超时）——引擎没完成就是判 FAIL，
不会挂死内核。`got < expect` 可能是丢操作（同一 MTE 通道上 4B put 丢过），
也可能是丢失更新，探针不区分，日志原样记录。

## 构建 / 运行（109 容器内）

```bash
cd probe/shmem_atomprobe
make DEVICE_HOME=/usr/local/Ascend/cann-9.2.1 \
     SHMEM_HOME=/data/shmem/install/shmem MPI_HOME=/usr/local/openmpi

export ASCEND_HOME_PATH=/usr/local/Ascend/cann-9.2.1
export ASCEND_RT_VISIBLE_DEVICES=0,1,4,5,6,7,8,9
export LD_LIBRARY_PATH=/data/shmem/install/shmem/lib:$LD_LIBRARY_PATH
export ATOM_IP_PORT=tcp://127.0.0.1:8766
for c in add_u32 add_u64 add_i32 add_f32 cas_u32 cas_u64 cas_i32 cas_f32 \
         sig_add intra2_u32; do
  timeout 180 /usr/local/openmpi/bin/mpirun --allow-run-as-root -np 8 \
    ./atomprobe $c
done
```

真双机（109+110）变体：`ATOM_IP_PORT=tcp://172.16.10.109:8766`，
mpirun 用 report §5 的 MPMD 模板（两半都要 `-x ATOM_IP_PORT`、
`-x ASCEND_HOME_PATH`、`-x LD_LIBRARY_PATH`）。

## 判读

- 每 case 一行：`AT <case> np=<n> expect=<e> got=<g> PASS|FAIL`。
- `UNSUPPORTED (launcher object missing)`：该 .asc 没编过——把编译错误
  留档，记为该类型/该 API 在 910C 不可用。
- `INIT rc=`：aclshmem 初始化失败，先按交付报告的 `ASCEND_HOME_PATH`
  要求排查，不是原子结论。
- `intra2_u32` 若 got==iters（等于 iters 而非 2×iters），说明 2 核没都
  跑到或到同一 PE 的环路被合并，判读时要区分「没并发」与「不原子」。
