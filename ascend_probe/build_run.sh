#!/bin/sh
# Round-56 rig. Round 55 located the impl tree at
# .../asc/impl/c_api/instr_impl/npu_arch_2201/sync_impl.h and it includes
# sync_impl/asc_set_flag_impl.h etc. -- so the real instruction bodies are
# in the sync_impl/ SUBDIR, dumped here for the first time. Also: event_t
# (the -Wcce-compat hint on asc_sync_notify's 3rd arg), and readelf
# sections of the C0 binary (MIX-execution check for the C0 run-3 anomaly).
# Stdin rule from r54 stands: every command takes a real file argument or
# runs behind a guard; nothing here can block on the terminal.
T=/usr/local/Ascend/ascend-toolkit/latest
B=$T/aarch64-linux/bin/bisheng
L=$T/aarch64-linux/lib64
G="-x asc --npu-soc=Ascend910_9382"
G="$G --cce-auto-infer-kernel-type=false -std=c++17 -O2"
cd /data/mywork/FlagCX || exit 1
mkdir -p /tmp/tc
S=ascend_probe/two_core.asc
INC="-I$T/include -L$L -lascendcl"
IC=$T/include
F=`find $T/ -name asc_set_flag_impl.h 2>/dev/null | head -1`
echo "F=$F"
if [ -n "$F" ]; then
  Z=`dirname $F`
  echo ==Z_LIST==
  ls $Z
  for f in asc_set_flag_impl.h asc_wait_flag_impl.h asc_sync_block_arrive_impl.h asc_sync_notify_impl.h asc_sync_wait_impl.h; do
    echo "== Z_$f"
    cat -n $Z/$f 2>/dev/null | head -44
  done
else
  echo NO_SETFLAG_IMPL_ON_DISK
fi
echo ==EVENT_T_DEF==
grep -rn "event_t" $IC/c_api 2>/dev/null | head -16
echo ==NOTIFY_DECL==
grep -rn -B2 -A4 "asc_sync_notify" $IC/c_api 2>/dev/null | head -30
echo ==PIPEM==
grep -rn "PIPE_M" $IC/c_api 2>/dev/null | head -6
for v in C0 F1 F3; do
  w=`echo $v | tr A-Z a-z`
  DF="-D$v"
  if [ $v = C0 ]; then DF=""; fi
  $B $G $DF $S -o /tmp/tc/r_$w $INC > /tmp/tc/e_$w.txt 2>&1
  echo ${v}_BUILD_RC=$?
done
for v in c0 f1 f3; do echo "== e_$v"; head -8 /tmp/tc/e_$v.txt; done
echo ==SECTIONS==
readelf -S /tmp/tc/r_c0 | head -26
export LD_LIBRARY_PATH=$L:$LD_LIBRARY_PATH
for v in c0 f1 f3; do
  for i in 1 2 3; do
    echo "== run $v $i"
    timeout 25 /tmp/tc/r_$v || echo ${v}_${i}_EXIT=$?
  done
done
