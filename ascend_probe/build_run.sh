#!/bin/sh
# Round-68 rig: GM-handshake block-barrier probe (barrier_probe.asc).
# This measures the candidate spelling for the LAST declared-absent
# in-node primitive of the ordering channel: namedBarrierSync /
# FLAGCX_DEVICE_SYNC_THREADS. Two AI cores, 20 rounds each; per round
# a core release-stores its WORK line, then its ARRIVAL line, then
# polls the peer arrival (>= r) with a per-poll asc_dcci_entire_all,
# and after crossing acquire-reads the peer WORK line - a seen arrival
# with stale work is an ordering violation (V), which is precisely
# the happens-before property a barrier must give, not just a
# rendezvous.
# Arms and PRE-REGISTERED predictions (written before any run):
#   BR x10  main protocol. Per run: BR_BUILD_RC=0, SYNC_RC=0,
#           F 0 0 (no spin exhaustion), V 0 0 (no ordering
#           violations), S0+S1>0 in >=8/10 (genuine waits - a
#           zero-spin run is the legitimate racing-ahead state,
#           recorded honestly as PS/SP zeros were in r61/r63).
#   N x2    -DBR_NO_INV negative control, poll WITHOUT per-poll
#           invalidate. Predicted signature = the H2 blind loop:
#           N_BUILD_RC=0, SYNC_RC=0 still (bounded spin cannot
#           deadlock), F 20 20 (BOTH cores exhaust all rounds),
#           V 0 0 (violations are only counted on crossings, and
#           a blind core never crosses).
# If the main arm ever shows V>0, the barrier reading is VOID and we
# re-measure - never ship a barrier that can cross on a stale gate.
T=/usr/local/Ascend/ascend-toolkit/latest
B=$T/aarch64-linux/bin/bisheng
L=$T/aarch64-linux/lib64
G="-x asc --npu-soc=Ascend910_9382"
G="$G --cce-auto-infer-kernel-type=false -std=c++17 -O2"
cd /data/mywork/FlagCX || exit 1
mkdir -p /tmp/tc
S=ascend_probe/barrier_probe.asc
INC="-I$T/include -L$L -lascendcl"
$B $G $S -o /tmp/tc/r_br $INC > /tmp/tc/e_br.txt 2>&1
echo BR_BUILD_RC=$?
$B $G -DBR_NO_INV $S -o /tmp/tc/r_n $INC > /tmp/tc/e_n.txt 2>&1
echo N_BUILD_RC=$?
echo "== e_br"; head -12 /tmp/tc/e_br.txt
echo "== e_n"; head -12 /tmp/tc/e_n.txt
export LD_LIBRARY_PATH=$L:$LD_LIBRARY_PATH
for i in 1 2 3 4 5 6 7 8 9 10; do
  echo "== run br $i"
  timeout 25 /tmp/tc/r_br || echo br_${i}_EXIT=$?
done
for i in 1 2; do
  echo "== run n $i"
  timeout 25 /tmp/tc/r_n || echo n_${i}_EXIT=$?
done
echo DONE68
