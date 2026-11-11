#!/bin/sh
# Round-61 rig. Gate passed 10/10 in r60; this round hardens and closes
# the last semantic hole:
#   R1 x30 soak (n -> 40 cumulative; any SP/PS hitting 20000, any OUT
#   mismatch, any non-zero SYNC_RC is logged, not averaged away).
#   D1 x5: is a DIRTY unflushed store preserved across
#   asc_dcci_entire_all (clean semantics) or discarded? DS = final GM
#   value of the dirty word, DE = the core's own volatile reload right
#   after the hammer. (5,5)=clean-and-keep, (0,0)=discard,
#   (5,0)/(0,5)=something we should know about.
#   C0 x2 baseline. No investigation dumps this round — ffts backlog
#   resumes only if the soak ever stumbles.
T=/usr/local/Ascend/ascend-toolkit/latest
B=$T/aarch64-linux/bin/bisheng
L=$T/aarch64-linux/lib64
G="-x asc --npu-soc=Ascend910_9382"
G="$G --cce-auto-infer-kernel-type=false -std=c++17 -O2"
cd /data/mywork/FlagCX || exit 1
mkdir -p /tmp/tc
S=ascend_probe/two_core.asc
INC="-I$T/include -L$L -lascendcl"
for v in C0 R1 D1; do
  w=`echo $v | tr A-Z a-z`
  DF="-D$v"
  if [ $v = C0 ]; then DF=""; fi
  $B $G $DF $S -o /tmp/tc/r_$w $INC > /tmp/tc/e_$w.txt 2>&1
  echo ${v}_BUILD_RC=$?
done
for v in c0 r1 d1; do echo "== e_$v"; head -12 /tmp/tc/e_$v.txt; done
export LD_LIBRARY_PATH=$L:$LD_LIBRARY_PATH
for i in 1 2; do
  echo "== run c0 $i"
  timeout 25 /tmp/tc/r_c0 || echo c0_${i}_EXIT=$?
done
for i in 1 2 3 4 5; do
  echo "== run d1 $i"
  timeout 25 /tmp/tc/r_d1 || echo d1_${i}_EXIT=$?
done
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
  echo "== run r1 $i"
  timeout 25 /tmp/tc/r_r1 || echo r1_${i}_EXIT=$?
done
