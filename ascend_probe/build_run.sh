#!/bin/sh
# Round-69 rig: release-pair ordering, linepack probe (linepack_probe.asc).
# r68 verdict (pre-registered rule executed): GM barrier VOID as spelled -
# 4/10 runs had V>0, always core0-about-core1, work stale under a seen
# arrival. This rig decides WHICH world: finite in-flight window (boring,
# pack+verify fixes it) vs structural flush non-ordering (barrier dead,
# shipped wording narrowed). 20 runs total, PASS matrix in the probe
# header, PRE-REGISTERED there before any run.
# Arms:
#   OLD x10 (-DLP_OLD, r68 layout, 100 rounds): reproduce the window at
#     density. Predicted per run: SYNC_RC=0, F 0 0, S0>>S1, R>0 in
#     >=7/10, AND V 0 0 (splits always settle within 50 refetches).
#   LP  x10 (arrival+work one line, one flush): predicted F 0 0, V 0 0,
#     AND R 0 0 in EVERY run (indivisible same-line publish). If R>0 but
#     V=0, packing splits too - verify protocol becomes the primitive.
# Any V>0 anywhere, any non-zero SYNC_RC, any timeout EXIT line: record
# verbatim, no averaging; V>0 on the LP arm = structural world.
T=/usr/local/Ascend/ascend-toolkit/latest
B=$T/aarch64-linux/bin/bisheng
L=$T/aarch64-linux/lib64
G="-x asc --npu-soc=Ascend910_9382"
G="$G --cce-auto-infer-kernel-type=false -std=c++17 -O2"
cd /data/mywork/FlagCX || exit 1
mkdir -p /tmp/tc
S=ascend_probe/linepack_probe.asc
INC="-I$T/include -L$L -lascendcl"
$B $G -DLP_OLD $S -o /tmp/tc/r_old $INC > /tmp/tc/e_old.txt 2>&1
echo OLD_BUILD_RC=$?
$B $G $S -o /tmp/tc/r_lp $INC > /tmp/tc/e_lp.txt 2>&1
echo LP_BUILD_RC=$?
echo "== e_old"; head -12 /tmp/tc/e_old.txt
echo "== e_lp"; head -12 /tmp/tc/e_lp.txt
export LD_LIBRARY_PATH=$L:$LD_LIBRARY_PATH
for i in 1 2 3 4 5 6 7 8 9 10; do
  echo "== run old $i"
  timeout 40 /tmp/tc/r_old || echo old_${i}_EXIT=$?
done
for i in 1 2 3 4 5 6 7 8 9 10; do
  echo "== run lp $i"
  timeout 40 /tmp/tc/r_lp || echo lp_${i}_EXIT=$?
done
echo DONE69
