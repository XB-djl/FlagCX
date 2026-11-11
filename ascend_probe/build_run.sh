#!/bin/sh
# Round-62: compile-only binding matrix for the traits wiring (F1..F5 in
# ordering_probe.asc). No hardware runs: semantics are measured already
# (rows 60/61, n=40); this round only decides which pointer-binding the
# CceAtomic follow-up can use. Each RC is per-variant; error tails show
# WHY on any RC!=0.
T=/usr/local/Ascend/ascend-toolkit/latest
B=$T/aarch64-linux/bin/bisheng
L=$T/aarch64-linux/lib64
G="-x asc --npu-soc=Ascend910_9382"
G="$G --cce-auto-infer-kernel-type=false -std=c++17 -O2"
cd /data/mywork/FlagCX || exit 1
mkdir -p /tmp/tc
S=ascend_probe/ordering_probe.asc
for f in 1 2 3 4 5; do
  $B $G -DFORM=$f -c $S -o /tmp/tc/op_f$f.o > /tmp/tc/oe_f$f.txt 2>&1
  echo F${f}_RC=$?
done
for f in 1 2 3 4 5; do
  echo "== oe_f$f"
  head -14 /tmp/tc/oe_f$f.txt
done
