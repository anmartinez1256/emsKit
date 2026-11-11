#!/bin/zsh
# Builds luikore's openEMS branch (pull request #228, commit 55ce11b) in a scratch folder and runs it against the
# installed fork on luikore's own benchmark model. Nothing is installed; ~/opt/openEMS is only read.
setopt interactivecomments
D=${0:A:h}; W=$D/work; mkdir -p $W
[[ -d $W/src ]] || git clone -q https://github.com/luikore/openEMS.git $W/src || exit 1
git -C $W/src checkout -q 55ce11b || exit 1
mkdir -p $W/build && cd $W/build || exit 1
P=$HOME/opt/openEMS
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # the Metal compiler is part of full Xcode
rm -f CMakeCache.txt
cmake ../src -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=$P -DFPARSER_ROOT_DIR=$P -DCSXCAD_ROOT_DIR=$P \
  -DTinyXML_INCLUDE_DIR=$P/include -DTinyXML_LIBRARY=$(ls $P/lib/libtinyxml*.dylib | head -1) > cmake.log 2>&1 || { tail -15 cmake.log; exit 1 }
make -j6 > make.log 2>&1 || { grep -m5 -B2 -A6 "error" make.log; exit 1 }
BIN=$(find $W/build -maxdepth 2 -type f -name openEMS -perm +111 | head -1)
[[ -x $BIN ]] || { print "no openEMS binary built"; exit 1 }
print "built $BIN"
python3 $D/compare.py $BIN $P/bin/openEMS $W/out 2>&1 | tee $D/result.txt
