
Install Instructions
------------------------
The following instructions are aimed at installing and building the Chapel programming language with HSA support enabled.

1. **Download:** The Chapel-HSA source code is available in the chpl-hsa branch of this repository. Clone this repository and switch to the chpl-hsa branch.
>git clone https://github.com/HSAFoundation/Chapel.git  
>git checkout -b chpl-hsa  

2. **Build:** From the top-level directory, source the util/setchplenv_hsa.bash script to set up the requisite envrironment for HSA support. Then run make to build the compiler and the runtime.
>cd chapel-1.12.0  
>source util/setchplenv_hsa.bash  
>make  

3. **Compile and Run:** Compile a program using the `chpl` command, and execute the resulting executable.
>chpl -o hsa-test exmaple/hsa-test.chpl  
>./hsa-test  

