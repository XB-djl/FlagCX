# cann-shmem MTE atomic probe (F1) — Ascend 910C.
#
# Host pass: MPI C++ compiler (or g++ + detected MPI paths).  Device pass:
# bisheng with the flags verified in test/kernel/ascend/Makefile.  Each .asc
# is a separate experiment: a type the soc rejects fails only its own unit
# (the compile rule is prefixed with '-'), and the host reports that case as
# UNSUPPORTED instead of aborting the run.
#
# Build: make DEVICE_HOME=<CANN> SHMEM_HOME=<cann-shmem> MPI_HOME=<openmpi>

DEVICE_HOME ?= /usr/local/Ascend/cann-9.2.1
SHMEM_HOME  ?= /data/shmem/install/shmem
MPI_HOME    ?= /usr/local/openmpi
CXX         ?= g++

include ../../makefiles/ascend.mk

BISHENG := $(ASCEND_BISHENG)
ifeq ($(strip $(BISHENG)),)
$(error bisheng not found under $(DEVICE_HOME))
endif

# MPI: prefer the wrapper, which knows its own include/library dirs; fall
# back to the layouts test/make.inc already resolves on this image.
MPICXX := $(firstword $(wildcard $(MPI_HOME)/bin/mpicxx) \
                     $(shell command -v mpicxx 2>/dev/null))
ifeq ($(strip $(MPICXX)),)
  ifeq ($(wildcard $(MPI_HOME)/include/mpi.h),)
    MPI_INC := $(firstword $(wildcard /usr/include/aarch64-linux-gnu/mpi) \
                          $(wildcard /usr/include/x86_64-linux-gnu/mpi))
    MPI_LIB := $(firstword \
        $(wildcard /usr/lib/aarch64-linux-gnu/openmpi/lib) \
        $(wildcard /usr/lib/x86_64-linux-gnu/openmpi/lib))
  else
    MPI_INC := $(MPI_HOME)/include
    MPI_LIB := $(MPI_HOME)/lib
  endif
  HOST_CC   := $(CXX)
  HOST_INC  := -I$(MPI_INC)
  HOST_MPI  := -L$(MPI_LIB) -lmpi -Wl,-rpath,$(MPI_LIB)
else
  HOST_CC   := $(MPICXX)
  HOST_INC  :=
  HOST_MPI  :=
endif
ifeq ($(strip $(MPI_INC)),)
$(info atomprobe: MPI through $(HOST_CC))
else
$(info atomprobe: MPI via $(HOST_CC) -I$(MPI_INC) -L$(MPI_LIB))
endif

SHMEM_INC := -I$(SHMEM_HOME)/include -I$(SHMEM_HOME)/include/device \
             -I$(SHMEM_HOME)/src/device -I$(SHMEM_HOME)/src
ASCENDC_INC := $(addprefix -I,$(firstword \
                 $(wildcard $(DEVICE_HOME)/aarch64-linux/include/ascendc) \
                 $(wildcard $(DEVICE_HOME)/include/ascendc) \
                 $(wildcard $(DEVICE_HOME)/compiler/include/ascendc)))
ACL_INC   := -I$(DEVICE_HOME)/include

ASC_FLAGS  := -x asc --npu-soc=$(ASCEND_SOC) \
              --cce-auto-infer-kernel-type=false -std=c++17 -O2 -c -fPIC \
              -DNDEBUG
HOST_FLAGS := -std=c++17 -O2 -fPIC -DOMPI_SKIP_MPICXX \
              $(HOST_INC) $(ACL_INC) $(SHMEM_INC)

ASCS := atom_add.asc atom_cas.asc atom_sig.asc
AOBJS := $(ASCS:.asc=.o)

.PHONY: all clean

all: atomprobe

atom_add.o: atom_add.asc atom_args.h
	-$(BISHENG) $(ASC_FLAGS) -o $@ $< $(SHMEM_INC) $(ACL_INC) $(ASCENDC_INC)

atom_cas.o: atom_cas.asc atom_args.h
	-$(BISHENG) $(ASC_FLAGS) -o $@ $< $(SHMEM_INC) $(ACL_INC) $(ASCENDC_INC)

atom_sig.o: atom_sig.asc atom_args.h
	-$(BISHENG) $(ASC_FLAGS) -o $@ $< $(SHMEM_INC) $(ACL_INC) $(ASCENDC_INC)

atom_probe_main.o: atom_probe_main.cpp
	$(HOST_CC) $(HOST_FLAGS) -c -o $@ $<

# Missing device units (failed compile) are simply not linked; the weak
# launcher references in the host resolve to null and the case prints
# UNSUPPORTED.
atomprobe: atom_probe_main.o $(AOBJS)
	$(HOST_CC) -o $@ atom_probe_main.o \
	  $$(ls atom_add.o atom_cas.o atom_sig.o 2>/dev/null) \
	  $(HOST_MPI) \
	  -L$(SHMEM_HOME)/lib -lshmem -Wl,-rpath,$(SHMEM_HOME)/lib \
	  -L$(DEVICE_LIB) $(DEVICE_LINK)

clean:
	rm -f atomprobe atom_probe_main.o $(AOBJS)
