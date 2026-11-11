#!/bin/sh
# Round-63: BUILD GATE for the ordered channel (feat/ascend-ordering
# commit 8c0e1b6). r63.txt leaves the tree on that branch; ascend_probe/
# is overlaid from verify/two-core.
#  (1) full library build with the device gate; error-line count + tail.
#  (2) gate object proofs: flagcxDevApiOrderedSmoke symbol present,
#      .aicore_binary section present, ZERO undefined flagcxAscend*
#      capability symbols (the absent plain/RMW/barrier paths must
#      remain uninstantiated by the gate).
#  (3) rig sanity: C0 x2 + R1 x3 - fast check the fetch/build/run path
#      is alive; semantics already proven at n=40, not re-soaked here.
T=/usr/local/Ascend/ascend-toolkit/latest
B=$T/aarch64-linux/bin/bisheng
L=$T/aarch64-linux/lib64
G="-x asc --npu-soc=Ascend910_9382"
G="$G --cce-auto-infer-kernel-type=false -std=c++17 -O2"
cd /data/mywork/FlagCX || exit 1
mkdir -p /tmp/tc
echo "== libbuild"
make USE_ASCEND=1 COMPILE_KERNEL=1 -j8 > /tmp/tc/lib.log 2>&1
echo LIB_RC=$?
echo ERR_CNT=$(grep -i -c "error:" /tmp/tc/lib.log)
grep -i "error:" /tmp/tc/lib.log | head -10
tail -4 /tmp/tc/lib.log
echo SO_SIZE=$(stat -c %s build/lib/libflagcx.so 2>/dev/null)
O=$(find . -name device_api.o 2>/dev/null | head -1)
echo OBJ=$O
echo NM_ORD=$(nm $O | grep -c flagcxDevApiOrderedSmoke)
echo AISEC=$(readelf -S $O | grep -c aicore_binary)
echo NM_UNDEF=$(nm -u $O | grep -c flagcxAscend)
echo "== rig"
S=ascend_probe/two_core.asc
INC="-I$T/include -L$L -lascendcl"
for v in C0 R1; do
  w=`echo $v | tr A-Z a-z`
  DF="-D$v"
  if [ $v = C0 ]; then DF=""; fi
  $B $G $DF $S -o /tmp/tc/r_$w $INC > /tmp/tc/e_$w.txt 2>&1
  echo ${v}_BUILD_RC=$?
done
for v in c0 r1; do echo "== e_$v"; head -8 /tmp/tc/e_$v.txt; done
export LD_LIBRARY_PATH=$L:$LD_LIBRARY_PATH
for i in 1 2; do
  echo "== run c0 $i"
  timeout 25 /tmp/tc/r_c0 || echo c0_${i}_EXIT=$?
done
for i in 1 2 3; do
  echo "== run r1 $i"
  timeout 25 /tmp/tc/r_r1 || echo r1_${i}_EXIT=$?
done
