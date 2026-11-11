#!/bin/sh
# Round-65: four-arm isolation matrix for the r64 fresh-gate failure
# (GATE_RC=2 on the forced rebuild of the gate TU: ld.lld reported
# undefined symbol flagcxAscendDeviceOpUnsupported.cube and .vector,
# i.e. a declared-absent capability got odr-used in the device image).
# Every arm is BUILD-ONLY. No rig runs (n=40 closed; rig untouched).
#  A1  reproduce r64 exactly, and log the real compile command via
#      make -n so flag provenance is auditable afterwards.
#  A2  rebuild the gate with -DFLAGCX_NO_ORDSMOKE through an
#      ASCEND_TEST_FLAGS override (the gate source carries the toggle
#      since a6a5ca8). Two self-evidence checks must hold before this
#      arm means anything: the override actually reached the command
#      line (A2_HAS_TOGGLE=1) and no header was lost to it (A2_HDR=0).
#      A2_RC=0 => the new smoke kernel is what pulls the trap.
#  A3  fresh-compile the gate in a detached worktree at #705 head
#      (feat/ascend-support, without any ordering implementation).
#      A3_RC!=0 => the break predates feat/ascend-ordering entirely.
#  A4  overload_probe.asc in four configs: which CceAtomic-shaped
#      overload a __gm__ argument binds to under bisheng clang15.
#      Error text names the bound trap: probeTmplTrap = catch-all
#      template deduced through __gm__; probePlainTrap = plain member.
T=/usr/local/Ascend/ascend-toolkit/latest
B=$T/aarch64-linux/bin/bisheng
cd /data/mywork/FlagCX || exit 1
mkdir -p /tmp/tc
O=test/kernel/ascend/build/obj/device_api.o
TF="-x asc --npu-soc=Ascend910_9382 --cce-auto-infer-kernel-type=false -std=c++17 -O2 -c -fPIC -DFLAGCX_ASCEND_DEVICE_COMPILE=1"

echo "== A1 reproduce =="
rm -f $O
make -n -C test/kernel/ascend USE_ASCEND=1 device_api.o > /tmp/tc/a1_cmd.log 2>&1
make -C test/kernel/ascend USE_ASCEND=1 device_api.o > /tmp/tc/a1.log 2>&1
echo A1_RC=$?
echo A1_COMPILED=$(grep -c "Compiling device_api" /tmp/tc/a1.log)
echo A1_UND=$(grep -c "undefined symbol" /tmp/tc/a1.log)
grep "error:" /tmp/tc/a1.log | head -4

echo "== A2 rebuild without ordered kernel =="
rm -f $O
make -n -C test/kernel/ascend USE_ASCEND=1 device_api.o \
  ASCEND_TEST_FLAGS="$TF -DFLAGCX_NO_ORDSMOKE" > /tmp/tc/a2_cmd.log 2>&1
echo A2_HAS_TOGGLE=$(grep -c FLAGCX_NO_ORDSMOKE /tmp/tc/a2_cmd.log)
make -C test/kernel/ascend USE_ASCEND=1 device_api.o \
  ASCEND_TEST_FLAGS="$TF -DFLAGCX_NO_ORDSMOKE" > /tmp/tc/a2.log 2>&1
echo A2_RC=$?
echo A2_UND=$(grep -c "undefined symbol" /tmp/tc/a2.log)
echo A2_HDR=$(grep -c "file not found" /tmp/tc/a2.log)
grep "error:" /tmp/tc/a2.log | head -4
ls -l $O 2>&1 | head -1

echo "== A3 fresh gate at 705 head =="
git worktree remove --force /tmp/wt705 2>/dev/null
rm -rf /tmp/wt705
git fetch --depth=1 origin feat/ascend-support > /tmp/tc/a3_fetch.log 2>&1
echo A3_FETCH_RC=$?
git rev-parse --short FETCH_HEAD
git worktree add --detach /tmp/wt705 FETCH_HEAD > /tmp/tc/a3_wt.log 2>&1
echo A3_WT_RC=$?
make -C /tmp/wt705/test/kernel/ascend USE_ASCEND=1 device_api.o > /tmp/tc/a3.log 2>&1
echo A3_RC=$?
echo A3_UND=$(grep -c "undefined symbol" /tmp/tc/a3.log)
grep "error:" /tmp/tc/a3.log | head -4

echo "== A4 overload binding probe =="
PB=ascend_probe/overload_probe.asc
BF="$B -x asc --npu-soc=Ascend910_9382 --cce-auto-infer-kernel-type=false -std=c++17 -O2 -c -fPIC"
$BF -DPROBE_OP_STORE $PB -o /tmp/tc/p1.o > /tmp/tc/p1.log 2>&1
echo P1_RC=$?
echo P1_TMPL=$(grep -c probeTmplTrap /tmp/tc/p1.log)
echo P1_PLAIN=$(grep -c probePlainTrap /tmp/tc/p1.log)
grep "error:" /tmp/tc/p1.log | head -2
$BF -DPROBE_OP_LOAD $PB -o /tmp/tc/p2.o > /tmp/tc/p2.log 2>&1
echo P2_RC=$?
echo P2_TMPL=$(grep -c probeTmplTrap /tmp/tc/p2.log)
echo P2_PLAIN=$(grep -c probePlainTrap /tmp/tc/p2.log)
grep "error:" /tmp/tc/p2.log | head -2
$BF -DPROBE_OP_STORE -DPROBE_NO_GM $PB -o /tmp/tc/p3.o > /tmp/tc/p3.log 2>&1
echo P3_RC=$?
echo P3_TMPL=$(grep -c probeTmplTrap /tmp/tc/p3.log)
grep "error:" /tmp/tc/p3.log | head -2
$BF -DPROBE_OP_LOAD -DPROBE_NO_GM $PB -o /tmp/tc/p4.o > /tmp/tc/p4.log 2>&1
echo P4_RC=$?
echo P4_TMPL=$(grep -c probeTmplTrap /tmp/tc/p4.log)
grep "error:" /tmp/tc/p4.log | head -2

git worktree remove --force /tmp/wt705 2>/dev/null
echo DONE65
