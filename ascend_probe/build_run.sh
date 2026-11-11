#!/bin/sh
# Round-53 rig: survey sync/cooperative APIs, build V0/V1/V2/V3 + coop
# variants, print every BUILD_RC, run each x3 under timeout.
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
echo ==SYNC_LIST==
grep -n "asc_sync" $H/c_api/sync/sync.h | head -30
echo ==SYNC_TOP==
sed -n '1,40p' $H/c_api/sync/sync.h
echo ==COOP_ACL==
grep -rn "CooperativeKernel" $T/include/acl | head -6
echo ==COOP_ASC==
grep -rni cooperative $H --include=*.h | head -8
for v in V0 V1 V2 V3; do
  w=`echo $v | tr A-Z a-z`
  $B $G -D$v $S -o /tmp/tc/r_$w $INC > /tmp/tc/e_$w.txt 2>&1
  echo ${v}_BUILD_RC=$?
done
$B $G -DV1 -DCOOP $S -o /tmp/tc/r_v1c $INC > /tmp/tc/e_v1c.txt 2>&1
echo V1C_BUILD_RC=$?
$B $G -DV2 -DCOOP $S -o /tmp/tc/r_v2c $INC > /tmp/tc/e_v2c.txt 2>&1
echo V2C_BUILD_RC=$?
for v in v0 v1 v2 v3 v1c v2c; do echo "== e_$v"; head -8 /tmp/tc/e_$v.txt; done
export LD_LIBRARY_PATH=$L:$LD_LIBRARY_PATH
for v in v0 v1 v2 v3 v1c v2c; do
  for i in 1 2 3; do
    echo "== run $v $i"
    timeout 20 /tmp/tc/r_$v || echo ${v}_${i}_EXIT=$?
  done
done
