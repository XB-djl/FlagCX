#!/bin/sh
# Round-64: BUILD FORENSICS for the NM_ORD=0 reading of r63. Question:
# is flagcxDevApiOrderedSmoke inside the gate object's device image,
# or was it never compiled (stale object / guard ate it)? Method:
#  (1) delete the gate object, rebuild it in isolation through the
#      gate Makefile rule (kills the staleness branch by construction,
#      and "Compiling device_api" line is the rebuild proof);
#  (2) nm on the fat object for the GUARDLESS control kernel (must be
#      >0 - host stub exists) vs the guarded ordered kernel (0 here is
#      the predicted artifact: no host half, symbol lives in the
#      embedded .aicore_binary blob only);
#  (3) pierce the blob: readelf --symbols and strings both searched
#      for the kernel name; either >0 = wiring is in the device image;
#  (4) warning count on the isolated rebuild.
# No rig runs this round (n=40 closed; rig untouched).
T=/usr/local/Ascend/ascend-toolkit/latest
B=$T/aarch64-linux/bin/bisheng
L=$T/aarch64-linux/lib64
cd /data/mywork/FlagCX || exit 1
mkdir -p /tmp/tc
O=test/kernel/ascend/build/obj/device_api.o
rm -f $O
make -C test/kernel/ascend USE_ASCEND=1 device_api.o > /tmp/tc/gate.log 2>&1
echo GATE_RC=$?
echo COMPILED=$(grep -c "Compiling device_api" /tmp/tc/gate.log)
echo WARNS=$(grep -c "warning:" /tmp/tc/gate.log)
grep -i "error:" /tmp/tc/gate.log | head -8
ls -l $O
echo NM_CTRL=$(nm $O | grep -c flagcxDevApiSmoke)
echo NM_ORD=$(nm $O | grep -c flagcxDevApiOrderedSmoke)
echo SYM_ORD=$(readelf --wide --symbols $O | grep -c OrderedSmoke)
echo STR_ORD=$(strings $O | grep -c OrderedSmoke)
echo AISEC=$(readelf -S $O | grep -c aicore_binary)
echo NM_UNDEF=$(nm -u $O | grep -c flagcxAscend)
head -12 /tmp/tc/gate.log
