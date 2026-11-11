#!/bin/sh
# Round-55 rig. r54 hung: sync_impl.h was not under asc/include, find came
# back empty, and `sed ... $Y` with no file read terminal stdin forever.
# Rule now enforced: every command gets a real file argument or is guarded;
# nothing in this script can read stdin.
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
echo ==IMPL_FIND==
Y=`find $T/ -name sync_impl.h 2>/dev/null | head -3`
echo "Y=$Y"
if [ -n "$Y" ]; then
  echo ==IMPL_FN==
  grep -n -A14 "asc_sync_block_arrive_impl\|asc_sync_block_wait_impl\|asc_sync_notify_impl\|asc_sync_wait_impl" $Y | head -90
  echo ==FLAG_IDS==
  grep -n "ffts\|FFTS\|flag" $Y | head -20
else
  echo NO_SYNC_IMPL_ON_DISK
fi
echo ==SIMT_CG==
head -50 $H/simt_api/cooperative_groups.h
echo ==CG_SYNC==
grep -n "sync\|tile\|this_" $H/simt_api/cooperative_groups.h | head -16
for v in C0 F1 F3; do
  w=`echo $v | tr A-Z a-z`
  D="-D$v"
  if [ $v = C0 ]; then D=""; fi
  $B $G $D $S -o /tmp/tc/r_$w $INC > /tmp/tc/e_$w.txt 2>&1
  echo ${v}_BUILD_RC=$?
done
for v in c0 f1 f3; do echo "== e_$v"; head -8 /tmp/tc/e_$v.txt; done
export LD_LIBRARY_PATH=$L:$LD_LIBRARY_PATH
for v in c0 f1 f3; do
  for i in 1 2 3; do
    echo "== run $v $i"
    timeout 25 /tmp/tc/r_$v || echo ${v}_${i}_EXIT=$?
  done
done
