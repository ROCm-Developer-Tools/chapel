# CL Files
CLFILES = test.cl
# Host compiler
CHPL_C = chpl
CHPL_C_FLAGS=
CHPL_C_FLAGS += --clfiles="$(CLFILES)"
#CHPL_C_FLAGS += --print-passes
#CHPL_C_FLAGS += --print-commands
#CHPL_C_FLAGS += --no-local-checks
#CHPL_C_FLAGS += --no-bounds-checks
CHPL_ENV_FLAGS=CHPL_SAVEC_DIR=tmp

OBJS = futures-cpu-gpu

.PHONY: clean all

all: $(OBJS)

futures-cpu-gpu: futures-cpu-gpu.chpl $(CLFILES)
	$(CHPL_ENV_FLAGS) $(CHPL_C) -o $@ $< $(CHPL_C_FLAGS) 

$(CLFILES):

clean:
	rm -rf *.hsaco $(OBJS)

test:
	./futures-cpu-gpu
