pushd /tmp
rm -rf lfs
unzip $SHARED_CLAUDE/lfs/lfs-pkgusr.zip
popd
cp -r /tmp/lfs/* .
