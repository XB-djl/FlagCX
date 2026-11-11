#!/bin/sh
# Round-58 rig. Variants: C0 baseline + H1 (doorbell poll hammered with
# asc_dcci_entire_all every spin — the last polling form; r57 showed
# per-line invalidate == no invalidate, both blind). Investigation: full
# sync.h (only ~60 lines — need the WHOLE 2201 branch: who is the SET
# counterpart of wait_flag_dev?), utils_type.h (home of event_t/pipe_t
# enums), CrossCoreSetFlag/WaitFlag in the C++ adv_api layer, set_flag_dev
# anywhere in either tree, and strings-bisheng evidence that
# ffts_cross_core_sync is a builtin. Nothing may read stdin.
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
echo ==SYNC_H_FULL==
cat -n $H/c_api/sync/sync.h 2>/dev/null | head -70
echo ==TYPE_ENUMS==
grep -n "event_t\|pipe_t\|enum" $M/utils_impl/utils_type.h 2>/dev/null | head -30
echo ==PB_IMPL_FULL==
cat -n $M/sync_impl/asc_pipe_barrier_impl.h 2>/dev/null | head -60
echo ==SET_FLAG_DEV==
grep -rn "set_flag_dev" $M $H 2>/dev/null | head -10
echo ==XC_CXX==
grep -rn "CrossCoreSetFlag\|CrossCoreWaitFlag" $H 2>/dev/null | head -10
echo ==XC_BODY==
grep -rn -A6 "CrossCoreSetFlag" $H 2>/dev/null | head -40
echo ==BUILTIN_STRINGS==
strings -a $B 2>/dev/null | grep -i "ffts_cross_core_sync\|set_flag_dev\|wait_flag_dev" | head -8
for v in C0 H1; do
  w=`echo $v | tr A-Z a-z`
  DF="-D$v"
  if [ $v = C0 ]; then DF=""; fi
  $B $G $DF $S -o /tmp/tc/r_$w $INC > /tmp/tc/e_$w.txt 2>&1
  echo ${v}_BUILD_RC=$?
done
for v in c0 h1; do echo "== e_$v"; head -8 /tmp/tc/e_$v.txt; done
export LD_LIBRARY_PATH=$L:$LD_LIBRARY_PATH
for v in c0 h1; do
  for i in 1 2 3; do
    echo "== run $v $i"
    timeout 25 /tmp/tc/r_$v || echo ${v}_${i}_EXIT=$?
  done
done
