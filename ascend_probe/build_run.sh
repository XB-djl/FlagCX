#!/bin/sh
# Round-66: decomposition matrix for the r65 contradiction (A2 proved the
# ordered smoke kernel body is the SOLE trigger of the undefined
# flagcxAscendDeviceOpUnsupported.cube/.vector, while every one of its six
# calls statically binds a clean __gm__ overload - P3/P4 killed the template
# catch-all and F1 killed the plain members). Two parts, all BUILD-ONLY:
#  B0-B3  gate source with the kernel split into single-call arms via
#         -DFLAGCX_ORD_STORE / _LOAD / _FENCE (make ASCEND_TEST_FLAGS
#         override; the A2 round proved this machinery works). B0 rebuilds
#         the full kernel (expect red, reproduce confirmation). Whichever
#         single arm first turns red names the guilty kind of call; all
#         three green with B0 red = a combination effect at the pass layer.
#  P1-P6  overload_probe.asc v2: members carry the real __aicore__
#         decorator (v1's failures were parse-time caller-qualification,
#         not binding), whole surface guarded to the device pass. P1/P2
#         are the binding positive control (expect RC=0), P3/P4 re-confirm
#         the no-gm rejection without the decorator artifact, P5/P6 are
#         the declared-absent mechanism control (expect RC=1 naming
#         probePlainTrap - the same signature as B0).
# The r65 A3 worktree arm is NOT repeated: it died on a missing untracked
# nlohmann/json.hpp (main-tree-only dependency), an environment artifact
# carrying zero information.
T=/usr/local/Ascend/ascend-toolkit/latest
B=$T/aarch64-linux/bin/bisheng
cd /data/mywork/FlagCX || exit 1
mkdir -p /tmp/tc
O=test/kernel/ascend/build/obj/device_api.o
TF="-x asc --npu-soc=Ascend910_9382 --cce-auto-infer-kernel-type=false -std=c++17 -O2 -c -fPIC -DFLAGCX_ASCEND_DEVICE_COMPILE=1"

gate() {
  n=$1; shift
  rm -f $O
  make -C test/kernel/ascend USE_ASCEND=1 device_api.o \
    ASCEND_TEST_FLAGS="$TF $*" > /tmp/tc/$n.log 2>&1
  echo ${n}_RC=$?
  echo ${n}_UND=$(grep -c "undefined symbol" /tmp/tc/$n.log)
  grep "error:" /tmp/tc/$n.log | head -2
  SZ=$(ls -l $O 2>/dev/null | awk '{print $5}')
  echo ${n}_SIZE=$SZ
}

echo "== B0 full kernel (expect red) =="
gate b0
echo "== B1 store only =="
gate b1 -DFLAGCX_ORD_STORE
echo "== B2 load only =="
gate b2 -DFLAGCX_ORD_LOAD
echo "== B3 fence only =="
gate b3 -DFLAGCX_ORD_FENCE

echo "== P probe v2 =="
PB=ascend_probe/overload_probe.asc
BF="$B -x asc --npu-soc=Ascend910_9382 --cce-auto-infer-kernel-type=false -std=c++17 -O2 -c -fPIC"
$BF -DPROBE_OP_STORE $PB -o /tmp/tc/p1.o > /tmp/tc/p1.log 2>&1
echo P1_RC=$?; echo P1_TMPL=$(grep -c probeTmplTrap /tmp/tc/p1.log)
grep "error:" /tmp/tc/p1.log | head -2
$BF -DPROBE_OP_LOAD $PB -o /tmp/tc/p2.o > /tmp/tc/p2.log 2>&1
echo P2_RC=$?; echo P2_TMPL=$(grep -c probeTmplTrap /tmp/tc/p2.log)
grep "error:" /tmp/tc/p2.log | head -2
$BF -DPROBE_OP_STORE -DPROBE_NO_GM $PB -o /tmp/tc/p3.o > /tmp/tc/p3.log 2>&1
echo P3_RC=$?; echo P3_TMPL=$(grep -c probeTmplTrap /tmp/tc/p3.log)
grep "error:" /tmp/tc/p3.log | head -2
$BF -DPROBE_OP_LOAD -DPROBE_NO_GM $PB -o /tmp/tc/p4.o > /tmp/tc/p4.log 2>&1
echo P4_RC=$?; echo P4_TMPL=$(grep -c probeTmplTrap /tmp/tc/p4.log)
grep "error:" /tmp/tc/p4.log | head -2
$BF -DPROBE_OP_PSTORE $PB -o /tmp/tc/p5.o > /tmp/tc/p5.log 2>&1
echo P5_RC=$?; echo P5_PLAIN=$(grep -c probePlainTrap /tmp/tc/p5.log)
grep "error:" /tmp/tc/p5.log | head -2
$BF -DPROBE_OP_PLOAD $PB -o /tmp/tc/p6.o > /tmp/tc/p6.log 2>&1
echo P6_RC=$?; echo P6_PLAIN=$(grep -c probePlainTrap /tmp/tc/p6.log)
grep "error:" /tmp/tc/p6.log | head -2

echo DONE66
