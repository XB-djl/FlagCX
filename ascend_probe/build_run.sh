#!/bin/sh
# Round-60 rig. Main event: R1 rendezvous x10 — forces the race on BOTH
# cores (consumer publishes READY then polls doorbell; producer polls
# READY before producing), every spin a real volatile load after a
# whole-L1 invalidate. PASS gate for P3 prototype: 10/10 with
# SYNC_RC=0, OUT 1 1 7 8, SP<20000, PS<20000 (and expect most PS>0 —
# that means the producer genuinely hammered and saw a fresh READY).
# Side investigations (ffts backlog, does not block the main line):
# dump matmul_cross_core_sync.h (CrossCoreSetFlag's likely home),
# refined strings (flag_dev family), locate the real event_t header.
# Nothing may read stdin.
T=/usr/local/Ascend/ascend-toolkit/latest
B=$T/aarch64-linux/bin/bisheng
L=$T/aarch64-linux/lib64
G="-x asc --npu-soc=Ascend910_9382"
G="$G --cce-auto-infer-kernel-type=false -std=c++17 -O2"
cd /data/mywork/FlagCX || exit 1
mkdir -p /tmp/tc
S=ascend_probe/two_core.asc
INC="-I$T/include -L$L -lascendcl"
H=$T/aarch64-linux/asc/include
M=$T/aarch64-linux/asc/impl/c_api/instr_impl/npu_arch_2201
echo ==CC_SYNC_H==
cat -n $T/aarch64-linux/asc/impl/adv_api/detail/matmul/param/matmul_cross_core_sync.h 2>/dev/null | head -70
echo ==STRINGS_FLAGDEV==
strings -a $B 2>/dev/null | grep -i "flag_dev" | head -12
echo ==EVENT_T_HOME==
V=`grep -rln "event_t" $M 2>/dev/null | head -3`
echo "V=$V"
if [ -n "$V" ]; then
  echo ==EVENT_T_LINES==
  grep -n "event_t" $V 2>/dev/null | head -12
fi
for v in C0 R1; do
  w=`echo $v | tr A-Z a-z`
  DF="-D$v"
  if [ $v = C0 ]; then DF=""; fi
  $B $G $DF $S -o /tmp/tc/r_$w $INC > /tmp/tc/e_$w.txt 2>&1
  echo ${v}_BUILD_RC=$?
done
for v in c0 r1; do echo "== e_$v"; head -12 /tmp/tc/e_$v.txt; done
export LD_LIBRARY_PATH=$L:$LD_LIBRARY_PATH
for i in 1 2; do
  echo "== run c0 $i"
  timeout 25 /tmp/tc/r_c0 || echo c0_${i}_EXIT=$?
done
for i in 1 2 3 4 5 6 7 8 9 10; do
  echo "== run r1 $i"
  timeout 25 /tmp/tc/r_r1 || echo r1_${i}_EXIT=$?
done
