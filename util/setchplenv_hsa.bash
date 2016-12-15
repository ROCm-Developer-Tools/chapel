# bash/zsh shell script to set the Chapel environment variables

# Find out filepath depending on shell
if [ -n "${BASH_VERSION}" ]; then
    filepath=${BASH_SOURCE[0]}
elif [ -n "${ZSH_VERSION}" ]; then
    filepath=${(%):-%N}
else
    echo "Error: setchplenv.bash can only be sourced from bash and zsh"
    return 1
fi

# Directory of setchplenv script, will not work if script is a symlink
DIR=$(cd "$(dirname "${filepath}")" && pwd)

# Shallow test to see if we are in the correct directory
# Just probe to see if we have a few essential subdirectories --
# indicating that we are probably in a Chapel root directory.
chpl_home=$( cd $DIR/../ && pwd )
if [ ! -d "$chpl_home/util" ] || [ ! -d "$chpl_home/compiler" ] || [ ! -d "$chpl_home/runtime" ] || [ ! -d "$chpl_home/modules" ]; then
    # Chapel home is assumed to be one directory up from setenvchpl.bash script
    echo "Error: \$CHPL_HOME is not where it is expected"
    return 1
fi

# Remove any previously existing CHPL_HOME paths
MYPATH=`$chpl_home/util/config/fixpath.py PATH`
exitcode=$?
MYMANPATH=`$chpl_home/util/config/fixpath.py MANPATH`

# Double check $MYPATH before overwriting $PATH
if [ -z "${MYPATH}" -o "${exitcode}" -ne 0 ]; then
    echo "Error:  util/config/fixpath.py failed"
    echo "        Make sure you have Python 2.5+"
    return 1
fi

export CHPL_HOME=$chpl_home
echo "Setting CHPL_HOME to $CHPL_HOME"

export CHPL_HOST_PLATFORM=`"$CHPL_HOME"/util/chplenv/chpl_platform.py`
echo "Setting CHPL_HOST_PLATFORM to $CHPL_HOST_PLATFORM"
export PATH="$CHPL_HOME"/bin/$CHPL_HOST_PLATFORM:"$CHPL_HOME"/util:"$MYPATH"
echo "Updating PATH to include $CHPL_HOME/bin/$CHPL_HOST_PLATFORM"
echo "                     and $CHPL_HOME/util"

#echo -n "Setting PORTAL_HOME "
#export PORTAL_HOME="$HOME"/mpix/xtq/p4-xtq-ib
#echo " to $PORTAL_HOME"

#echo -n "Setting PATH for yod, updating PATH to include "
#export PATH="$PORTAL_HOME"/bin:"$PATH"
#echo " $PORTAL_HOME/bin"

#echo -n "Updating LD_LIBRARY_PATH "
#export LD_LIBRARY_PATH="$CHPL_HOME"/third-party/hsa/HSA-Runtime-AMD/lib:$LD_LIBRARY_PATH
#echo " to $LD_LIBRARY_PATH"

echo -n "Setting CHPL_COMM"
export CHPL_COMM=none
echo " to none"

echo -n "Setting CHPL_TASKS"
export CHPL_TASKS=atmi
echo " to atmi"

echo -n "Setting CHPL_ATOMICS"
export CHPL_ATOMICS=intrinsics
echo " to intrinsics"

#echo -n "Setting CONDUIT "
#export CONDUIT=portals4
#echo " as portals4"

#echo -n "Setting CHPL_COMM_SUBSTRATE "
#export CHPL_COMM_SUBSTRATE=portals4
#echo " as portals4"

#echo -n "Setting GASNET_MAX_SEGSIZE"
#export GASNET_MAX_SEGSIZE=419430400
#echo " to 419430400"

#echo -n "Setting CHPL_GASNET_SEGMENT"
#export CHPL_GASNET_SEGMENT=fast
#echo " to fast"

#echo -n "Setting CHPL_GASNET_CFG_OPTIONS"
#export CHPL_GASNET_CFG_OPTIONS="--enable-portals4 --with-portals4home=$PORTAL_HOME --enable-pthreads --disable-udp  --disable-mpi-compat --disable-mpi --disable-mxm"
#echo  " --enable-portals4 --with-portals4home=$PORTAL_HOME --enable-pthreads --disable-udp  --disable-mpi-compat --disable-mpi --disable-mxm "

echo -n "Disabling NUMA"
export CHPL_HWLOC_CFG_OPTIONS=" --disable-libnuma"
echo " done"

echo -n "Setting CHPL_HWLOC"
export CHPL_HWLOC=hwloc
echo " to hwloc"

echo -n "Disabling LLVM support"
export CHPL_LLVM=none
echo " done"

if [ "$1" == "debug" ]; then
    echo "Debugging mode on"
    export CHPL_DEVELOPER=1
    export CHPL_COMM_DEBUG=1
    export CHPL_GASNET_DEBUG=1
    export GASNET_BACKTRACE=1
    export CHPL_DEBUG=1
fi

echo -n "Setting CHPL_ROCM"
export CHPL_ROCM=1
echo " to 1"

echo -n "Setting CHPL_LOCALE_MODEL"
export CHPL_LOCALE_MODEL=hsa
echo " to hsa"

echo -n "Setting CHPL_TARGET_COMPILER"
export CHPL_TARGET_COMPILER=hsa
echo " to hsa"

echo -n "Setting CHPL_ROCM"
export CHPL_ROCM=1
echo " to 1"

export MANPATH="$CHPL_HOME"/man:"$MYMANPATH"
echo "Updating MANPATH to include $CHPL_HOME/man"
