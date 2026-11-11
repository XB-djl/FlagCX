#!/bin/sh
# Two-core round-trip rig: build V1/V2/V3, run each x3 under timeout.
# Compile self-evidence first (RC + head of each error log), then runs.
T=/usr/local/Ascend/ascend-toolkit/latest
B=$T/aarch64-linux/bin/bisheng
L=$T/aarch64-linux/lib64
G="-x asc --npu-soc=Ascend910_9382"
G="$G --cce-auto-infer-kernel-type=false -std=c++17 -O2"
cd /data/mywork/FlagCX || exit 1
mkdir -p /tmp/tc
S=ascend_probe/two_core.asc
INC="-I$T/include -L$L -lascendcl"
$B $G -DV1 $S -o /tmp/tc/r_v1 $INC > /tmp/tc/e_v1.txt 2>&1
echo V1BUILD_RC=$?
$B $G -DV2 $S -o /tmp/tc/r_v2 $INC > /tmp/tc/e_v2.txt 2>&1
echo V2BUILD_RC=$?
$B $G -DV3 $S -o /tmp/tc/r_v3 $INC > /tmp/tc/e_v3.txt 2>&1
echo V3BUILD_RC=$?
for v in v1 v2 v3; do echo "== e_$v"; head -8 /tmp/tc/e_$v.txt; done
export LD_LIBRARY_PATH=$L:$LD_LIBRARY_PATH
for v in v1 v2 v3; do
  for i in 1 2 3; do
    echo "== run $v $i"
    timeout 30 /tmp/tc/r_$v || echo ${v}_${i}_EXIT=$?
  done
done
