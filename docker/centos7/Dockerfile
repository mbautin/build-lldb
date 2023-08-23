FROM docker.io/yugabyteci/yb_build_infra_centos7_x86_64:v2023-04-07T00_19_49
COPY scripts /tmp/scripts
RUN yum install -y rh-python38
RUN bash /tmp/scripts/build_lldb.sh
