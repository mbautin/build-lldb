#!/usr/bin/env bash

mkdir -p downloads
docker run -it \
  --mount=type=bind,src=$PWD/scripts,dst=/tmp/scripts,readonly \
  --mount=type=bind,src=$PWD/downloads,dst=/tmp/downloads \
  yugabyteci/yb_build_infra_centos7_x86_64:v2023-04-07T00_19_49 \
  bash -c "
    bash /tmp/scripts/build_lldb.sh
  "
