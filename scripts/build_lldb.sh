#!/usr/bin/env bash

set -euo pipefail -x


yum install -y rh-python38-python-devel
yum install -y libedit-devel libxml2-devel ncurses-devel swig
yum install -y libatomic pcre2-devel

python_prefix=/opt/rh/rh-python38/root
export PATH=$python_prefix/bin:$PATH
if [[ ! -d venv ]]; then
  python3 -m venv venv
fi
. venv/bin/activate
pip install llvm-installer
llvm_url=$(

python3 -c "
from llvm_installer import LlvmInstaller
import sys_detection

local_sys_conf = sys_detection.local_sys_conf()
llvm_installer = LlvmInstaller(
    short_os_name_and_version=local_sys_conf.short_os_name_and_version(),
    architecture=local_sys_conf.architecture)
llvm_url = llvm_installer.get_llvm_url(major_llvm_version=16)
print(llvm_url)
"

)

cd /opt/yb-build/llvm
llvm_tarball=${llvm_url##*/}
llvm_dir_name=${llvm_tarball%.tar.gz}
if [[ ! -d $llvm_dir_name ]]; then
  curl -L -O "$llvm_url"
  tar xzf "$llvm_tarball"
fi

compiler_prefix=$PWD/$llvm_dir_name
compiler_bin_dir=$compiler_prefix/bin

timestamp=$( date +%s )

arch=$( uname -m )
lldb_version=16.0.6-yb-2
# Still use /opt/yb-build/llvm because it exists on many systems.
lldb_prefix=/opt/yb-build/llvm/yb-lldb-v${lldb_version}-${timestamp}-centos7-$arch
lldb_build_dir=${lldb_prefix}-build

#rm -rf "${lldb_prefix}"
#rm -rf "${lldb_build_dir}"

mkdir -p "${lldb_build_dir}"
cd "$lldb_build_dir"
swig_version=4.1.1
mkdir -p swig
cd swig
swig_dir_name=swig-${swig_version}
swig_tarball=${swig_dir_name}.tar.gz
swig_dir=$PWD/$swig_dir_name
if [[ ! -f "$swig_tarball" ]]; then
  curl --silent -L -o "$swig_tarball" https://github.com/swig/swig/archive/refs/tags/v${swig_version}.tar.gz
fi
tar xzf "$swig_tarball"

# SWIG will be installed in a subdirectory of the LLDB installation.
swig_prefix=${lldb_prefix}/swig

export CC=$compiler_bin_dir/clang
export CXX=$compiler_bin_dir/clang++

unwind_lib_dir=${compiler_prefix}/lib/x86_64-unknown-linux-gnu
lldb_libunwind_dir=${lldb_prefix}/lib/x86_64-unknown-linux-gnu
mkdir -p "${lldb_libunwind_dir}"
# Put the eventual rpath where LLDB's newly built libunwind will be installed first.
libunwind_ld_flags="-lunwind -Wl,-rpath=${lldb_libunwind_dir} -L${unwind_lib_dir} -Wl,-rpath=${unwind_lib_dir}"

cd "${swig_dir}"
if [[ ! -d $swig_prefix ]]; then
export LDFLAGS="${libunwind_ld_flags}"
./autogen.sh
./configure --prefix=${swig_prefix}
make
make install
unset LDFLAGS
else
echo "Skipping building SWIG"
fi

export PATH=$compiler_bin_dir:$PATH
export PATH=${swig_prefix}/bin:$PATH

ld_flags_arr=(
-L${swig_prefix}/lib
-Wl,-rpath=${swig_prefix}/lib
${libunwind_ld_flags}
-L${python_prefix}/usr/lib64
-Wl,-rpath=${python_prefix}/usr/lib64
)
ld_flags="${ld_flags_arr[*]}"


cd "$lldb_build_dir"
curl -L -O https://github.com/yugabyte/llvm-project/archive/refs/tags/llvmorg-16.0.6-yb-2.tar.gz
tar xzf llvmorg-16.0.6-yb-2.tar.gz
mv llvm-project-llvmorg-16.0.6-yb-2 llvm-project
llvm_src_dir=$lldb_build_dir/llvm-project

llvm_build_dir=$lldb_build_dir/llvm-build
mkdir -p "$llvm_build_dir"
cd "$llvm_build_dir"

cmake_cmd_line=(
cmake -G Ninja -DLLVM_ENABLE_PROJECTS="lldb;clang"
-S "${llvm_src_dir}/llvm"
-DLLVM_ENABLE_RUNTIMES=libunwind
-DCMAKE_C_COMPILER=$CC
-DCMAKE_CXX_COMPILER=$CXX
-DCMAKE_INSTALL_PREFIX=${lldb_prefix}
-DLLDB_ENABLE_LIBEDIT=ON
-DLLDB_ENABLE_CURSES=ON
-DLLDB_ENABLE_LZMA=ON
-DLLDB_ENABLE_LIBXML2=ON
-DLLDB_ENABLE_PYTHON=ON
-DCMAKE_BUILD_TYPE=Release
-DCMAKE_CXX_FLAGS="-I${swig_prefix}/include -I${python_prefix}/usr/include/python3.8"
-DPython3_LIBRARIES=${python_prefix}/usr/lib64/libpython3.8.so
-DPython3_EXECUTABLE=${python_prefix}/usr/bin/python3.8
-DPython3_INCLUDE_DIRS=${python_prefix}/usr/include
-DSWIG_EXECUTABLE=${swig_prefix}/bin/swig
-DBUILD_SHARED_LIBS=ON
"-DCMAKE_EXE_LINKER_FLAGS=${ld_flags}"
"-DCMAKE_SHARED_LINKER_FLAGS=${ld_flags}"
"-DLLVM_TARGETS_TO_BUILD=AArch64;X86"
)

set -x
"${cmake_cmd_line[@]}"
num_cpus=$( cat /proc/cpuinfo | grep '^processor' | wc -l )
ninja -j${num_cpus} clang
ninja -j${num_cpus} lldb
ninja install

# Make swig use the right libunwind
patchelf --set-rpath "${lldb_prefix}/lib/x86_64-unknown-linux-gnu" swig/bin/swig
