#!/bin/sh
# Round-59 rig. Two questions, one round:
#  (1) Is the polling blindness (r57/r58 SP=20000 x12) hardware or the
#      compiler hoisting the load? H2/H3 poll through volatile __gm__
#      (guaranteed real load per iteration); if bisheng rejects
#      volatile GM, the build error settles it another way.
#  (2) Who is the real cross-core SETTER? sync.h 2201 has no set-side
#      for wait_flag_dev; AscendC's CrossCoreSetFlag (used by
#      matmul_client.h) has its template in the IMPL tree — locate and
#      dump it, plus uncut strings evidence for set_flag_dev-family
#      builtins, plus utils_intf.h where event_t/pipe_t enums live
#      (utils_type.h had neither — r58 TYPE_ENUMS came back empty).
# Nothing may read stdin; every dump guarded.
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
echo ==XC_FILE==
X=`grep -rln "CrossCoreSetFlag" $T/aarch64-linux/asc/impl 2>/dev/null | head -3`
echo "X=$X"
if [ -n "$X" ]; then
  echo ==XC_DEF==
  grep -n -B2 -A22 "void CrossCoreSetFlag" $X 2>/dev/null | head -48
fi
echo ==STRINGS_SET==
strings -a $B 2>/dev/null | grep -i "set_flag_dev\|cross_core_set\|SET_INTRA" | head -14
echo ==INTF_FILE==
W=`find $T/ -name utils_intf.h 2>/dev/null | head -1`
echo "W=$W"
if [ -n "$W" ]; then
  echo ==INTF_ENUMS==
  grep -n "event_t\|pipe_t\|PIPE_\|EVT" "$W" 2>/dev/null | head -40
fi
echo ==EVENTT_TYPEDEF==
grep -rn "event_t;\|} event_t" $M $H 2>/dev/null | head -6
for v in C0 H2 H3; do
  w=`echo $v | tr A-Z a-z`
  DF="-D$v"
  if [ $v = C0 ]; then DF=""; fi
  $B $G $DF $S -o /tmp/tc/r_$w $INC > /tmp/tc/e_$w.txt 2>&1
  echo ${v}_BUILD_RC=$?
done
for v in c0 h2 h3; do echo "== e_$v"; head -12 /tmp/tc/e_$v.txt; done
export LD_LIBRARY_PATH=$L:$LD_LIBRARY_PATH
for v in c0 h2 h3; do
  for i in 1 2 3; do
    echo "== run $v $i"
    timeout 25 /tmp/tc/r_$v || echo ${v}_${i}_EXIT=$?
  done
done
