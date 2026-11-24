/*************************************************************************
 * Copyright (c) 2026 BAAI. All rights reserved.
 *
 * Kernel argument block shared by the three probe .asc units.
 ************************************************************************/

#ifndef SHMEM_ATOMPROBE_ARGS_H_
#define SHMEM_ATOMPROBE_ARGS_H_

struct AtomArgs {
  unsigned long long ffts;
  unsigned long long dst; // symmetric heap word, local VA (engine maps by pe)
  int pe;
  int iters;
};

#endif // SHMEM_ATOMPROBE_ARGS_H_
