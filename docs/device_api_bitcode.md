# Device API bitcode

FlagCX can build Device API LLVM bitcode for NVIDIA CUDA, Iluvatar CoreX,
Hygon DU, PPU, and Huawei Ascend. A kernel consumer links
`libflagcx_device.bc` and includes the headers from the same build. Choose an
architecture supported by the installed SDK.

## Build from the repository root

The `device_bitcode` target builds `libflagcx.so` with `COMPILE_KERNEL=1`, then
builds bitcode with the same adaptor and CommTraits flags. Every platform and
architecture uses the same `BUILDDIR` (by default, `build/`):

```sh
make USE_NVIDIA=1 DEVICE_BITCODE_ARCH=sm_90 device_bitcode

make USE_ILUVATAR=1 DEVICE_BITCODE_ARCH=ivcore11 device_bitcode

make USE_DU=1 DEVICE_HOME=/opt/dtk CCL_HOME=/opt/dtk \
  DEVICE_BITCODE_ARCH=gfx906 device_bitcode

make USE_PPU=1 DEVICE_HOME=/usr/local/PPU_SDK \
  DEVICE_BITCODE_ARCH=ppu001 BUILDDIR="$PWD/build/ppu-bc" device_bitcode

make USE_ASCEND=1 USE_SHMEM=1 COMPILE_KERNEL=1 \
  SHMEM_HOME=/usr/local/Ascend/shmem/latest \
  DEVICE_BITCODE_ARCH=Ascend910_9382 device_bitcode
```

`build/` contains `lib/libflagcx.so`, `lib/libflagcx_device.bc`, and consumer
headers in `include/`. Repeated builds reuse unchanged objects and bitcode;
changes to included project headers rebuild the bitcode. Each build directory
uses one platform, architecture, and adaptor configuration. Use a fresh build
directory when changing those settings. The root build selects CUDA SHMEM,
Default, or CCL according to its normal Makefile options and installed NCCL
headers; the bitcode receives that exact selection.

## PPU Device IR for FlagTree

The PPU build uses `DefaultBackend<PpuPlatform>` and compiles the common
`flagcx_device_wrapper_impl.h`, including Scalar IR, Unified IR, and the
compatibility entry points. One `libflagcx_device.bc` contains all 152 public
Device IR entry points currently listed in `bindings/ir/public_symbols.txt`,
including inter-node operations. The optimizer preserves that complete list;
the build fails if any listed function has no definition in the final IR.

The PPU example above writes `lib/libflagcx_device.bc`, `lib/libflagcx.so`,
and matching consumer headers under `build/ppu-bc/`. Readable LLVM IR is
available at `build/ppu-bc/obj/llvm_ir/libflagcx_device.ll`. Supply the BC to
FlagTree through `extern_libs={"libflagcx_device": path_to_bc}` using its PPU
backend. Linking, code generation, and device execution are validated in
FlagTree; exporting an inter-node entry point does not establish transport
support in the runtime configuration.

PPU bitcode compilation uses the SDK's native HGGC Clang frontend with
`-x hggc --hggc-device-only -emit-llvm`, rather than CUDA/NVPTX compilation.
`DEVICE_BITCODE_ARCH` is passed to Clang as `--ppu-arch` and to the native
`hgcc` host-library kernel build as `-arch`. Choose a single architecture
accepted by both drivers in the installed SDK; `ppu001` is an example.

By default, the PPU build uses `clang`, `opt`, `llvm-dis`, and `llvm-as` from
`$(DEVICE_HOME)/bin`. Set `PPU_LLVM_BIN` when these tools are installed
elsewhere, or override `PPU_CLANG`, `OPT`, `LLVM_DIS`, and `LLVM_AS` individually.
Use LLVM tools from the same SDK build as the compiler so they understand
its PPU intrinsics. These overrides also work as environment variables when
building a wheel.

## Ascend Device IR

The Ascend build uses `CommTraits<AclshmemBackend>` when `USE_SHMEM=1`
(`DefaultBackend<AscendPlatform>` otherwise) and compiles the same
`flagcx_device_wrapper_impl.h` with bisheng, the toolkit's clang 15 CCE
frontend:

```sh
bisheng -x asc --npu-soc=<soc> --cce-aicore-only -emit-llvm -c ...
```

The CCE target is a two-core machine, so one build produces two modules
instead of one:

- `lib/libflagcx_device.bc` — AI Vector (AIV) core module;
- `lib/libflagcx_device-cube.bc` — AI Cube (AIC) core module.

Both export the 152 public entry points from `bindings/ir/public_symbols.txt`;
the build fails if a listed symbol is missing or was internalized. It also
checks the CCE triple and each module's core marker symbol
(`__init_kfc_workspace_addr.vector` / `.cube`). Readable IR is written to
`obj/llvm_ir/ascend/libflagcx_device.ll` and `libflagcx_device-cube.ll`.

The toolkit has no `opt`; `llvm-link --internalize` with the same public
symbol list performs the internalization step. `DEVICE_BITCODE_ARCH` is the
soc name reported by `aclrtGetSocName()` (`Ascend910_9382` on the 910C);
`bisheng` and `llvm-link` are located from `DEVICE_HOME`, then `PATH`, and
can be overridden with `BISHENG` / `LLVM_LINK`.

Consumption is an LLVM-level pipeline (for example FlagTree / Triton-Ascend on
Ascend): the bisheng driver compiles CCE from `.asc` sources and does not
accept LLVM bitcode input, so the modules are linked into the consumer's LLVM
pipeline rather than passed back to the driver. Generation and module content
are validated on real 910C hardware; upstream CI does not build Ascend
bitcode.

## Include bitcode in a Python wheel

Set `FLAGCX_BITCODE_ARCH` when installing from the repository root:

```sh
FLAGCX_ADAPTOR=nvidia FLAGCX_BITCODE_ARCH=sm_90 \
  pip install . -v --no-build-isolation

FLAGCX_ADAPTOR=iluvatar FLAGCX_BITCODE_ARCH=ivcore11 \
  pip install . -v --no-build-isolation

FLAGCX_ADAPTOR=du DEVICE_HOME=/opt/dtk CCL_HOME=/opt/dtk \
  FLAGCX_BITCODE_ARCH=gfx906 pip install . -v --no-build-isolation

FLAGCX_ADAPTOR=ppu DEVICE_HOME=/usr/local/PPU_SDK \
  FLAGCX_BITCODE_ARCH=ppu001 pip install . -v --no-build-isolation
```

The wheel path currently covers nvidia, iluvatar, du, musa, and ppu. Build
Ascend bitcode with the make target above and package the two modules
yourself.

The wheel includes `flagcx/lib/libflagcx_device.bc`, `libflagcx.so`, and the
matching headers under `flagcx/include/`. The BC build selects
`COMPILE_KERNEL=1` for the host library, which is required for Device API net
contexts. An explicit `COMPILE_KERNEL=0` conflicts with this build and fails.

## Resource lifetime

Complete kernels launched directly by the application before destroying the
DevComm, DevMem, or Window they use, or finalizing their communicator. The same
rule applies to captured graph replays. FlagCX does not discover external
streams or track graph capture/replay.

Host communication submissions save completion events at their submission
boundaries. Communicator cleanup waits for these records and accepted proxy/RMA
work without synchronizing the whole device. DevComm, DevMem, and Window cleanup
retain their first work snapshot and accepted RMA/FIFO prefix across retries,
so later independent host work
is not added to that snapshot. Existing stream ordering and explicit dependencies
still apply.

If cleanup fails, keep the handle and retry it. Resources already released remain
cleared; the remaining event, mapping, allocation, or plugin owner is retained.
Do not submit new work through a resource whose cleanup has started.
