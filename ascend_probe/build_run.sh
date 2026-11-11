#!/bin/sh
# Round-57 rig. r56 proved $T/include/c_api does not exist (the empty
# EVENT_T/NOTIFY/PIPEM greps) — headers come from bisheng's builtin search
# path rooted at asc/include, same trap as r48. So this round greps the
# TWO REAL TREES: asc/include (public) and asc/impl (instruction bodies),
# and opens utils_impl/utils_impl.h where set_flag/wait_flag/
# ffts_cross_core_sync live (r56 proved the five sync_impl files only
# #define macros onto them). Variants: C0 baseline, P1 doorbell poll with
# per-iteration line invalidate, P2 same without invalidate.
# Nothing here can read stdin; every dump has a guard or a real file.
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
echo ==TREE_CHECK==
ls -d $H $M $M/utils_impl 2>/dev/null
echo ==UTILS_LIST==
ls $M/utils_impl 2>/dev/null
echo ==UTILS_HEAD==
cat -n $M/utils_impl/utils_impl.h 2>/dev/null | head -80
echo ==FFTS_DEF==
grep -rn "ffts_cross_core_sync" $M $H 2>/dev/null | head -8
echo ==SETFLAG_DEF==
grep -rn "set_flag" $M $H 2>/dev/null | head -14
echo ==WAITDEV_DEF==
grep -rn "wait_flag_dev" $M $H 2>/dev/null | head -8
echo ==EVENT_T==
grep -rn "event_t" $H 2>/dev/null | head -20
echo ==NOTIFY_PUB==
grep -rn -B2 -A4 "asc_sync_notify" $H/c_api 2>/dev/null | head -30
echo ==PIPEM==
grep -rn "PIPE_M" $H/c_api 2>/dev/null | head -6
for v in C0 P1 P2; do
  w=`echo $v | tr A-Z a-z`
  DF="-D$v"
  if [ $v = C0 ]; then DF=""; fi
  $B $G $DF $S -o /tmp/tc/r_$w $INC > /tmp/tc/e_$w.txt 2>&1
  echo ${v}_BUILD_RC=$?
done
for v in c0 p1 p2; do echo "== e_$v"; head -8 /tmp/tc/e_$v.txt; done
echo ==SECTIONS==
readelf -S /tmp/tc/r_c0 | grep -i "aicore\|aivector\|npu\|binary" | head -10
export LD_LIBRARY_PATH=$L:$LD_LIBRARY_PATH
for v in c0 p1 p2; do
  for i in 1 2 3; do
    echo "== run $v $i"
    timeout 25 /tmp/tc/r_$v || echo ${v}_${i}_EXIT=$?
  done
done
