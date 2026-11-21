// mc2gate — host-only MC2 resource-allocation gate for 910C (npu_arch 2201).
// Flow mirrors moe_dispatch_direct_invoke_sample host side:
//   HcclCommInitAll(2) -> HcclGetCommName -> Mc2CcTilingConfig(name, 6, AlltoAll alg)
//   -> GetTiling x2 -> HcomGetCommHandleByGroup -> HcclAllocComResourceByTiling -> D2H dump.
// engine: argv[1] (OpExecuteConfig: 2=AICPU_TS, 3=AIV, 6=CCU_SCHED); devices: argv[2],argv[3].
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <thread>
#include "acl/acl.h"
#include "hccl/hccl.h"
#include "hccl/hccl_comm.h"
#include "tiling/hccl/hccl_tiling.h"

using namespace optiling;

// Declared here to avoid pinning the asc-devkit header tree in this probe.
extern "C" HcclResult HcclAllocComResourceByTiling(HcclComm comm, void* stream, void* mc2Tiling, void** opResCtx);
extern "C" HcclResult HcomGetCommHandleByGroup(const char* group, HcclComm* comm);

struct TD {
    Mc2InitTiling init;
    Mc2CcTiling cc;
};

static int32_t g_rc[2] = {-99, -99};
static void* g_ctx[2] = {nullptr, nullptr};

static void DumpCtx(int rank, void* ctx)
{
    uint64_t buf[64];
    memset(buf, 0, sizeof(buf));
    aclError r = aclrtMemcpy(buf, sizeof(buf), ctx, sizeof(buf), ACL_MEMCPY_DEVICE_TO_HOST);
    printf("[rank%d] D2H rc=%d\n", rank, (int)r);
    if (r != ACL_SUCCESS) {
        return;
    }
    for (int i = 0; i < 64; i += 4) {
        printf("[rank%d] w%02d..%02d = %016lx %016lx %016lx %016lx\n",
            rank, i, i + 3, buf[i], buf[i + 1], buf[i + 2], buf[i + 3]);
    }
}

static void OneRank(int rank, aclrtContext ctx, aclrtStream stream, HcclComm comm, uint8_t engine)
{
    aclError ar = aclrtSetCurrentContext(ctx);
    printf("[rank%d] setCtx rc=%d\n", rank, (int)ar);

    char name[128] = {0};
    HcclResult hr = HcclGetCommName(comm, name);
    printf("[rank%d] GetCommName rc=%d name='%s'\n", rank, (int)hr, name);
    if (hr != HCCL_SUCCESS) {
        g_rc[rank] = (int)hr;
        return;
    }

    AscendC::Mc2CcTilingConfig cfg(std::string(name), 6, "AlltoAll=level0:fullmesh;level1:pairwise");
    cfg.SetCommEngine(engine);

    TD* td = new TD();
    memset(td, 0, sizeof(*td));
    uint32_t g0 = cfg.GetTiling(td->init);
    uint32_t g1 = cfg.GetTiling(td->cc);
    printf("[rank%d] GetTiling rc=%u,%u engine=%u\n", rank, g0, g1, (unsigned)engine);
    if (g0 != 0 || g1 != 0) {
        g_rc[rank] = -2;
        return;
    }

    HcclComm handle = nullptr;
    hr = HcomGetCommHandleByGroup(name, &handle);
    printf("[rank%d] GetCommHandleByGroup rc=%d handle=%p\n", rank, (int)hr, (void*)handle);
    if (handle == nullptr) {
        handle = comm;
    }

    void* mctx = nullptr;
    hr = HcclAllocComResourceByTiling(handle, stream, td, &mctx);
    printf("[rank%d] AllocComResourceByTiling rc=%d ctx=%p\n", rank, (int)hr, mctx);
    g_rc[rank] = (int)hr;
    g_ctx[rank] = mctx;
    if (mctx != nullptr) {
        DumpCtx(rank, mctx);
    }
}

int main(int argc, char** argv)
{
    setvbuf(stdout, nullptr, _IONBF, 0);
    uint8_t engine = argc > 1 ? (uint8_t)atoi(argv[1]) : 2;
    int32_t devs[2] = {0, 4};
    if (argc > 3) {
        devs[0] = atoi(argv[2]);
        devs[1] = atoi(argv[3]);
    }
    printf("[main] engine=%u devs=%d,%d\n", (unsigned)engine, devs[0], devs[1]);

    aclError ar = aclInit(nullptr);
    printf("[main] aclInit rc=%d\n", (int)ar);

    aclrtContext ctxs[2] = {nullptr, nullptr};
    aclrtStream streams[2] = {nullptr, nullptr};
    for (int i = 0; i < 2; ++i) {
        aclrtSetDevice(devs[i]);
        ar = aclrtCreateContext(&ctxs[i], devs[i]);
        printf("[main] dev%d createCtx rc=%d ctx=%p\n", devs[i], (int)ar, (void*)ctxs[i]);
        ar = aclrtCreateStream(&streams[i]);
        printf("[main] dev%d createStream rc=%d\n", devs[i], (int)ar);
    }

    HcclComm comms[2] = {nullptr, nullptr};
    HcclResult hr = HcclCommInitAll(2, devs, comms);
    printf("[main] HcclCommInitAll rc=%d\n", (int)hr);
    if (hr != HCCL_SUCCESS) {
        return 1;
    }

    std::thread t0(OneRank, 0, ctxs[0], streams[0], comms[0], engine);
    std::thread t1(OneRank, 1, ctxs[1], streams[1], comms[1], engine);
    t0.join();
    t1.join();

    printf("RESULT engine=%u rc0=%d rc1=%d ctx0=%p ctx1=%p\n",
        (unsigned)engine, g_rc[0], g_rc[1], g_ctx[0], g_ctx[1]);
    return 0;
}
