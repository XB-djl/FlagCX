#!/bin/sh
# Round-67: FIX-VERIFICATION matrix. r66 closed the r64/r65 contradiction:
# single-call gate arms were store-only GREEN / fence-only GREEN /
# load-only RED (undefined flagcxAscendDeviceOpUnsupported.cube/.vector) -
# the load catch-all template deduced T=__gm__ uint32_t, matched by
# identity, and bisheng let it beat the non-template ordered overload.
# Fix 04acc20 removes the load/store catch-alls from the traits.
# Arms, all BUILD-ONLY (no rig; n=40 closed):
#  F0  full ordered kernel, default build: RC=0 = the fix itself
#  F1  load-only arm: RC=0 (direct proof the gm load now binds+links)
#  F2  store-only arm: RC=0 (regression)
#  F3  fence-only arm: RC=0 (regression)
#  F4  FLAGCX_NO_ORDSMOKE: RC=0 (r65 A2 control, should stay green)
#  F5  root library build (make USE_ASCEND=1 COMPILE_KERNEL=1 -j8):
#      LIB_RC, error count, libflagcx.so size - the delivery evidence
#  P1..P8  overload_probe v3 (stubs decorated with __aicore__ - v2's all-
#      arm failure at :37/:43 was the same caller-qualification rule, an
#      own goal, not data): pre-fix set P1/P2 reproduces B1/B2 in
#      isolation; P3/P4 measures the swallow with nothing ordered
#      competing; P5/P6 are the plain-trap link-signature controls;
#      P7/P8 (PROBE_NO_TMPL) verify the fixed overload shape standalone.
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
  rc=$?
  echo ${n}_RC=$rc
  echo ${n}_UND=$(grep -c "undefined symbol" /tmp/tc/$n.log)
  grep "error:" /tmp/tc/$n.log | head -2
  SZ=$(ls -l $O 2>/dev/null | awk '{print $5}')
  echo ${n}_SIZE=$SZ
}

echo "== F fixed-tree gate builds =="
gate f0
gate f1 -DFLAGCX_ORD_LOAD
gate f2 -DFLAGCX_ORD_STORE
gate f3 -DFLAGCX_ORD_FENCE
gate f4 -DFLAGCX_NO_ORDSMOKE

echo "== F5 root library build =="
make USE_ASCEND=1 COMPILE_KERNEL=1 -j8 > /tmp/tc/f5.log 2>&1
echo F5_RC=$?
echo F5_ERR=$(grep -c "error:" /tmp/tc/f5.log)
SO=$(find . -maxdepth 4 -name libflagcx.so 2>/dev/null | head -1)
echo F5_SO=$SO
echo F5_SIZE=$(stat -c %s "$SO" 2>/dev/null)
tail -3 /tmp/tc/f5.log

echo "== P probe v3 =="
PB=ascend_probe/overload_probe.asc
BF="$B -x asc --npu-soc=Ascend910_9382 --cce-auto-infer-kernel-type=false -std=c++17 -O2 -c -fPIC"
p() {
  n=$1; shift
  $BF "$@" $PB -o /tmp/tc/$n.o > /tmp/tc/$n.log 2>&1
  echo ${n}_RC=$?
  echo ${n}_UND_TMPL=$(grep -c "undefined symbol: probeTmplTrap" /tmp/tc/$n.log)
  echo ${n}_UND_PLAIN=$(grep -c "undefined symbol: probePlainTrap" /tmp/tc/$n.log)
  grep "error:" /tmp/tc/$n.log | head -2
}
p p1 -DPROBE_OP_STORE
p p2 -DPROBE_OP_LOAD
p p3 -DPROBE_OP_STORE -DPROBE_NO_GM
p p4 -DPROBE_OP_LOAD -DPROBE_NO_GM
p p5 -DPROBE_OP_PSTORE
p p6 -DPROBE_OP_PLOAD
p p7 -DPROBE_OP_LOAD -DPROBE_NO_TMPL
p p8 -DPROBE_OP_STORE -DPROBE_NO_TMPL

echo DONE67
