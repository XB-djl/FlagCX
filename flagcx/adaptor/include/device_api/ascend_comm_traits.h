/*************************************************************************
 * Copyright (c) 2026 BAAI. All rights reserved.
 ************************************************************************/

#ifndef FLAGCX_ASCEND_COMM_TRAITS_H_
#define FLAGCX_ASCEND_COMM_TRAITS_H_

#include "default_comm_traits.h"

// Ascend (__NPU_ARCH__ 2201) barrier-slot channel.
//
// Measured on 910C: the ordered scalar surface that works is a 32-bit
// volatile store followed by the dcci pair, and a dcci pair followed by
// a 32-bit volatile load (see the fence note in device_utils.h and the
// S16 handshake spelling). Plain 64-bit scalar remote accesses are the
// shape that freezes, so the slot channel is narrowed to 32 bits here;
// barrier epochs stay well below 2^32 in any run horizon.
template <> struct BarrierSlotOps<AscendPlatform> {
#if defined(__CCE_IS_AICORE__)
  static FLAGCX_DEVICE_INLINE_DECORATOR void
  store(uint64_t *p, uint64_t value, flagcxDeviceMemoryOrder_t) {
    *(volatile uint32_t *)p = (uint32_t)value;
    asc_dcci_entire_out();
    asc_dcci_entire_all();
  }
  static FLAGCX_DEVICE_INLINE_DECORATOR uint64_t
  load(uint64_t *p, flagcxDeviceMemoryOrder_t) {
    asc_dcci_entire_out();
    asc_dcci_entire_all();
    return (uint64_t)*(volatile const uint32_t *)p;
  }
#else
  using Atomic = typename PlatformTraits<AscendPlatform>::Atomic;
  static FLAGCX_DEVICE_INLINE_DECORATOR void
  store(uint64_t *p, uint64_t value, flagcxDeviceMemoryOrder_t order) {
    Atomic::store(p, value, order);
  }
  static FLAGCX_DEVICE_INLINE_DECORATOR uint64_t
  load(uint64_t *p, flagcxDeviceMemoryOrder_t order) {
    return Atomic::load(p, order);
  }
#endif
};

using DeviceAPI = CommTraits<DefaultBackend<AscendPlatform>>;

#endif // FLAGCX_ASCEND_COMM_TRAITS_H_
