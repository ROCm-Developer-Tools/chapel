
Install Instructions
------------------------
The following instructions are aimed at installing and building the Chapel programming language with ROCm support enabled.

1. Install the Radeon Open Compute Platform. Instructions are listed here: https://github.com/RadeonOpenCompute/ROCm

   Generally, you should be able to:
   	 sudo apt-get update
   	 sudo apt-get install rocm

2. Download the Chapel ROCm enabled source code. Clone this repository and switch to the chpl-hsa branch.
   	 git clone https://github.com/RadeonOpenCompute/Chapel.git  
  	 git checkout -b chpl-hsa-master  

3. Build: From the top-level directory, source the util/setchplenv_hsa.bash script to set up the requisite environment for ROCm support. Then run make to build the compiler and the runtime.
   	 cd Chapel
	 source util/setchplenv_hsa.bash  
	 make  

4. Compile and Run: Compile a program using the `chpl` command, and execute the resulting executable.
   	 cd test/release/examples/hsa
   	 chpl -o loopy loopy.chpl
	 ./loopy

