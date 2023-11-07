#!/usr/bin/env bash
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

. ./ci/common.sh

do_install() {
    linux_get_dependencies

    export_or_prefix

    . ./ci/linux-install-openresty.sh
    echo "THIS IS OPENSSL PREFIX $openssl_prefix"
    openssl_prefix=$openssl_prefix ./utils/linux-install-luarocks.sh
    ./ci/linux-install-etcd-client.sh
}

install_openssl_3(){
    # required for openssl 3.x config
    cpanm IPC/Cmd.pm
    wget --no-check-certificate https://www.openssl.org/source/openssl-3.1.3.tar.gz
    tar xvf openssl-*.tar.gz
    cd openssl-3.1.3
    OPENSSL3_PREFIX=$(pwd)
    ./config
    make -j $(nproc)
    make install
    export LD_LIBRARY_PATH=$OPENSSL3_PREFIX${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    ldconfig
    export openssl_prefix="$OPENSSL3_PREFIX"
    cd ..
}



script() {
    export_or_prefix
    openresty -V

    sudo rm -rf /usr/local/apisix
    install_openssl_3
    # run the test case in an empty folder
    mkdir tmp && cd tmp
    cp -r ../utils ./
    luarocks config --local variables.OPENSSL_LIBDIR "$openssl_prefix"; \
    luarocks config --local variables.OPENSSL_INCDIR "$openssl_prefix/include" ;
    # install APISIX by luarocks
    luarocks install $APISIX_MAIN > build.log 2>&1 || (cat build.log && exit 1)
    cp ../bin/apisix /usr/local/bin/apisix

    # show install files
    luarocks show apisix

    sudo PATH=$PATH apisix help
    sudo PATH=$PATH apisix init
    sudo PATH=$PATH apisix start
    sudo PATH=$PATH apisix quit
    for i in {1..10}
    do
        if [ ! -f /usr/local/apisix/logs/nginx.pid ];then
            break
        fi
        sleep 0.3
    done
    sudo PATH=$PATH apisix start
    sudo PATH=$PATH apisix stop

    # apisix cli test
    # todo: need a more stable way

    grep '\[error\]' /usr/local/apisix/logs/error.log > /tmp/error.log | true
    if [ -s /tmp/error.log ]; then
        echo "=====found error log====="
        cat /usr/local/apisix/logs/error.log
        exit 1
    fi
}

case_opt=$1
shift

case ${case_opt} in
do_install)
    do_install "$@"
    ;;
script)
    script "$@"
    ;;
esac
