#!/bin/zsh
# Build upstream master (openEMS 1d710c2, CSXCAD fdff4b5; sources exported by git archive into $MASTER_DIR/src/CSXCAD and
# $MASTER_DIR/src/openEMS) into $MASTER_DIR/prefix. MASTER_DIR (default: this folder) must exist with src/ in it.
# Same dependencies as the fork's build folders (Homebrew, plus fparser and TinyXML from the fork's install,
# OPENEMS_PREFIX, default ~/opt/openEMS); 4 make jobs. Never installs anywhere but $MASTER_DIR/prefix.
set -e
M=${MASTER_DIR:-${0:A:h}}
IN=${OPENEMS_PREFIX:-$HOME/opt/openEMS}
P=$M/prefix
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
mkdir -p $M/build-csxcad $M/build-openems $P
cd $M/build-csxcad
cmake $M/src/CSXCAD -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$P -DCMAKE_PREFIX_PATH="$IN" \
  -DTinyXML_INCLUDE_DIR=$IN/include -DTinyXML_LIBRARY=$IN/lib/libtinyxml.dylib > $M/cmake_csxcad.log 2>&1
nice -n 5 make -j4 > $M/make_csxcad.log 2>&1
make install > $M/install_csxcad.log 2>&1
cd $M/build-openems
cmake $M/src/openEMS -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$P -DCMAKE_PREFIX_PATH="$P;$IN" \
  -DCSXCAD_ROOT_DIR=$P -DTinyXML_INCLUDE_DIR=$IN/include \
  -DTinyXML_LIBRARY=$IN/lib/libtinyxml.dylib > $M/cmake_openems.log 2>&1
nice -n 5 make -j4 > $M/make_openems.log 2>&1
make install > $M/install_openems.log 2>&1
echo "built: $(ls $P/lib | tr '\n' ' ')"
grep -h "Metal GPU backend\|HIP" $M/cmake_openems.log | head -3
