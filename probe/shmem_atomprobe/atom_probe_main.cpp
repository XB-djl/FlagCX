/*************************************************************************
 * Copyright (c) 2026 BAAI. All rights reserved.
 *
 * Host side of the cann-shmem MTE atomic probe (F1).  Mirrors the aclshmem
 * adaptor's init recipe (value-initialized attr, MTE engine, PE0-star
 * bootstrap) so a pass here is evidence about the same path the backend
 * runs.
 *
 * Usage: mpirun -np N ./atomprobe <case>; exit 0 = PASS.
 *   add_{u32,u64,i32,f32}  every PE adds 1 into PE0's word, iters times
 *   cas_{u32,u64,i32,f32}  every PE CAS-increments PE0's word, iters times
 *   sig_add                every PE signal-ADDs into PE0's word
 *   intra2_u32             two AIV cores of one PE add into their own word
 *
 * Judging: the target word must reach iters*npes (iters*2 for intra2_u32).
 * A lower value can be a dropped MTE op as much as a lost update — the
 * line prints got vs expect; it does not separate the two.
 *
 * Env: ATOM_IP_PORT (default tcp://127.0.0.1:8766), ATOM_ITERS (1000),
 *      ATOM_HEAP (1 GiB), ATOM_DEV (default: the MPI rank's visible index).
 ************************************************************************/

#include <mpi.h>

#include <acl/acl.h>
#include <shmem.h>

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unistd.h>

enum CaseKind { KIND_ADD = 0, KIND_CAS = 1, KIND_SIG = 2 };

// Weak: a .asc that fails to build removes only its own launcher, and the
// case is reported UNSUPPORTED instead of aborting the whole run.
extern "C" int atomLaunchAdd(int type, aclrtStream stream,
                             unsigned long long dst, int pe, int iters,
                             int ncores) __attribute__((weak));
extern "C" int atomLaunchCas(int type, aclrtStream stream,
                             unsigned long long dst, int pe, int iters,
                             int ncores) __attribute__((weak));
extern "C" int atomLaunchSig(aclrtStream stream, unsigned long long dst,
                             int pe, int iters) __attribute__((weak));

struct CaseDef {
  const char *name;
  int kind;
  int type; // 0 u32, 1 u64, 2 i32, 3 f32
  int ncores;
  int self; // target the calling PE instead of PE0
  int wide; // bytes to read back
};

static const CaseDef kCases[] = {
    {"add_u32", KIND_ADD, 0, 1, 0, 4},
    {"add_u64", KIND_ADD, 1, 1, 0, 8},
    {"add_i32", KIND_ADD, 2, 1, 0, 4},
    {"add_f32", KIND_ADD, 3, 1, 0, 4},
    {"cas_u32", KIND_CAS, 0, 1, 0, 4},
    {"cas_u64", KIND_CAS, 1, 1, 0, 8},
    {"cas_i32", KIND_CAS, 2, 1, 0, 4},
    {"cas_f32", KIND_CAS, 3, 1, 0, 4},
    {"sig_add", KIND_SIG, 0, 1, 0, 4},
    {"intra2_u32", KIND_ADD, 0, 2, 1, 4},
    {"intra2_i32", KIND_ADD, 2, 2, 1, 4},
};
enum { NCASES = (int)(sizeof(kCases) / sizeof(kCases[0])) };

static int envInt(const char *name, int dflt) {
  const char *v = getenv(name);
  return (v != nullptr && v[0] != '\0') ? atoi(v) : dflt;
}

static unsigned long long envULL(const char *name, unsigned long long dflt) {
  const char *v = getenv(name);
  return (v != nullptr && v[0] != '\0') ? strtoull(v, nullptr, 0) : dflt;
}

// SHMEM_UID_SESSION_ID takes the bootstrap address without the transport
// prefix, ip_port takes it with one (same split as the adaptor).
static void setSessionId(const char *ipPort) {
  const char *value = ipPort;
  if (strncmp(value, "tcp://", 6) == 0)
    value += 6;
  setenv("SHMEM_UID_SESSION_ID", value, 0);
}

static unsigned long long readWord(void *word, int wide) {
  unsigned long long v = 0;
  if (wide == 8) {
    aclrtMemcpy(&v, 8, word, 8, ACL_MEMCPY_DEVICE_TO_HOST);
  } else {
    uint32_t w = 0;
    aclrtMemcpy(&w, 4, word, 4, ACL_MEMCPY_DEVICE_TO_HOST);
    v = w;
  }
  return v;
}

int main(int argc, char **argv) {
  MPI_Init(&argc, &argv);
  int rank = 0;
  int npes = 1;
  MPI_Comm_rank(MPI_COMM_WORLD, &rank);
  MPI_Comm_size(MPI_COMM_WORLD, &npes);

  int ci = -1;
  if (argc > 1) {
    for (int i = 0; i < NCASES; ++i)
      if (strcmp(argv[1], kCases[i].name) == 0)
        ci = i;
  }
  if (ci < 0) {
    if (rank == 0)
      fprintf(stderr, "usage: atomprobe <case> (see README.md)\n");
    MPI_Finalize();
    return 2;
  }
  const CaseDef &c = kCases[ci];

  const int iters = envInt("ATOM_ITERS", 1000);
  const unsigned long long heapBytes = envULL("ATOM_HEAP", (1ULL << 30));
  const int dev = envInt("ATOM_DEV", rank);
  const char *ipp = getenv("ATOM_IP_PORT");
  if (ipp == nullptr || ipp[0] == '\0')
    ipp = "tcp://127.0.0.1:8766";

  int haveFn = 0;
  if (c.kind == KIND_ADD)
    haveFn = atomLaunchAdd != nullptr;
  else if (c.kind == KIND_CAS)
    haveFn = atomLaunchCas != nullptr;
  else
    haveFn = atomLaunchSig != nullptr;

  int aclOk = aclInit(nullptr) == ACL_SUCCESS &&
              aclrtSetDevice(dev) == ACL_SUCCESS;
  aclrtStream stream = nullptr;
  if (aclOk)
    aclOk = aclrtCreateStream(&stream) == ACL_SUCCESS;

  aclshmemx_init_attr_t attr{};
  attr.my_pe = rank;
  attr.n_pes = npes;
  snprintf(attr.ip_port, sizeof(attr.ip_port), "%s", ipp);
  attr.local_mem_size = heapBytes;
  attr.option_attr.data_op_engine_type = ACLSHMEM_DATA_OP_MTE;
  static aclshmemx_uniqueid_t uid;
  uid.my_pe = rank;
  uid.n_pes = npes;
  attr.comm_args = &uid;
  setSessionId(ipp);

  int initRc = aclOk ? aclshmemx_init_attr(ACLSHMEMX_INIT_WITH_DEFAULT, &attr)
                     : -1;

  void *word = (initRc == 0) ? aclshmem_malloc(64) : nullptr;
  if (word != nullptr)
    aclrtMemset(word, 64, 0, 64);
  MPI_Barrier(MPI_COMM_WORLD);

  const int pe = c.self ? rank : 0;
  int launchRc = -1;
  if (haveFn && word != nullptr) {
    if (c.kind == KIND_ADD)
      launchRc = atomLaunchAdd(c.type, stream, (unsigned long long)word, pe,
                               iters, c.ncores);
    else if (c.kind == KIND_CAS)
      launchRc = atomLaunchCas(c.type, stream, (unsigned long long)word, pe,
                               iters, c.ncores);
    else
      launchRc = atomLaunchSig(stream, (unsigned long long)word, pe, iters);
  }
  int syncRc = (launchRc == 0) ? (int)aclrtSynchronizeStream(stream) : -1;

  const int mine = (rank == 0 || c.self);
  const unsigned long long expect =
      (unsigned long long)iters * (c.self ? (unsigned long long)c.ncores
                                          : (unsigned long long)npes);
  unsigned long long got = 0;
  if (mine && launchRc == 0) {
    for (int i = 0; i < 400; ++i) { // 20 s at 50 ms
      got = readWord(word, c.wide);
      if (got == expect)
        break;
      usleep(50000);
    }
  }
  // Float cases arrive as a bit pattern; compare the value they encode, not
  // the pattern itself.
  int reached = (got == expect);
  if (c.type == 3 && c.kind != KIND_SIG) {
    float f = 0.0f;
    memcpy(&f, &got, sizeof(f));
    reached = (f == (float)expect);
  }
  int ok = mine ? reached : 1;
  int okMin = 0;
  MPI_Allreduce(&ok, &okMin, 1, MPI_INT, MPI_MIN, MPI_COMM_WORLD);
  const int pass = okMin && haveFn && launchRc == 0 && syncRc == 0 &&
                   initRc == 0 && word != nullptr;

  if (rank == 0) {
    if (initRc != 0)
      printf("AT %s INIT rc=%d FAIL\n", c.name, initRc);
    else if (!haveFn)
      printf("AT %s UNSUPPORTED (launcher object missing)\n", c.name);
    else if (launchRc != 0)
      printf("AT %s launch rc=%d FAIL\n", c.name, launchRc);
    else if (syncRc != 0)
      printf("AT %s stream-sync rc=%d FAIL\n", c.name, syncRc);
    else if (c.type == 3 && c.kind != KIND_SIG) {
      float f = 0.0f;
      memcpy(&f, &got, sizeof(f));
      printf("AT %s np=%d expect=%llu got=%.0f %s\n", c.name, npes, expect, f,
             pass ? "PASS" : "FAIL");
    } else {
      printf("AT %s np=%d expect=%llu got=%llu %s\n", c.name, npes, expect,
             got, pass ? "PASS" : "FAIL");
    }
  }

  MPI_Barrier(MPI_COMM_WORLD);
  if (word != nullptr)
    aclshmem_free(word);
  if (initRc == 0)
    aclshmem_finalize();
  if (stream != nullptr)
    aclrtDestroyStream(stream);
  if (aclOk)
    aclrtResetDevice(dev);
  aclFinalize();
  MPI_Finalize();
  return pass ? 0 : 1;
}
