#
#  Copyright 2017 Advanced Micro Devices, Inc.
#  
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

# CL Files
CLFILES = test.cl
# Host compiler
CHPL_C = chpl
CHPL_C_FLAGS=
#CHPL_C_FLAGS += --clfiles="$(CLFILES)"
CHPL_C_FLAGS += --print-passes
#CHPL_C_FLAGS += --print-commands
#CHPL_C_FLAGS += --no-local-checks
#CHPL_C_FLAGS += --no-bounds-checks
CHPL_ENV_FLAGS=CHPL_SAVEC_DIR=tmp

OBJS = nw

.PHONY: clean all

all: $(OBJS)

nw: nw.chpl $(CLFILES)
	$(CHPL_ENV_FLAGS) $(CHPL_C) -o $@ $< $(CHPL_C_FLAGS) 

$(CLFILES):

clean:
	rm -rf *.hsaco $(OBJS)

test:
	./nw
