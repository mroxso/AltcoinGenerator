#!/bin/sh
# This script is an experiment to clone litecoin into a
# brand new coin + blockchain.
# The script will perform the following steps:
# 1) create first a docker image with ubuntu ready to build and run the new coin daemon
# 2) clone GenesisH0 and mine the genesis blocks of main, test and regtest networks in the container (this may take a lot of time)
# 3) clone litecoin
# 4) replace variables (keys, merkle tree hashes, timestamps..)
# 5) build new coin
# 6) run 4 docker nodes and connect to each other
#
# By default the script uses the regtest network, which can mine blocks
# instantly. If you wish to switch to the main network, simply change the
# CHAIN variable below

# change the following variables to match your new coin
COIN_NAME="MyCoin"
COIN_UNIT="MYC"
# 42 million coins at total (litecoin total supply is 84000000)
TOTAL_SUPPLY="42000000"
MAINNET_PORT="54321"
TESTNET_PORT="54322"
PHRASE="Some newspaper headline that describes something that happened today"
# First letter of the wallet address. Check https://en.bitcoin.it/wiki/List_of_address_prefixes
PUBKEY_CHAR="20"
# number of blocks to wait to be able to spend coinbase UTXO's
COINBASE_MATURITY="100"
# leave CHAIN empty for main network, -regtest for regression network and -testnet for test network
CHAIN="-regtest"
# this is the amount of coins to get as a reward of mining the block of height 1. if not set this will default to 50
#PREMINED_AMOUNT=10000
# warning: change this to your own pubkey to get the genesis block mining reward
# use https://www.bitaddress.org/ to generate a new pubkey or run python ./wallet-generator.py and copy the Public Key: string
GENESIS_REWARD_PUBKEY="044e0d4bc823e20e14d66396a64960c993585400c53f1e6decb273f249bfeba0e71f140ffa7316f2cdaaae574e7d72620538c3e7791ae9861dfe84dd2955fc85e8"

CLIENT_VERSION="1.0.0.0"

# dont change the following variables unless you know what you are doing
LITECOIN_BRANCH="0.14"
GENESISHZERO_REPOS="https://github.com/lhartikk/GenesisH0"
LITECOIN_REPOS="https://github.com/litecoin-project/litecoin.git"
LITECOIN_PUB_KEY="040184710fa689ad5023690c80f3a49c8f13f8d45b8c857fbcbc8bc4a8e4d3eb4b10f4d4604fa08dce601aaf0f470216fe1b51850b4acf21b179c45070ac7b03a9"
LITECOIN_MERKLE_HASH="97ddfbbae6be97fd6cdf3e7ca13232a3afff2353e29badfab7f73011edd4ced9"
LITECOIN_MAIN_GENESIS_HASH="12a765e31ffd4059bada1e25190f6e98c99d9714d334efa41a195a7e7e04bfe2"
LITECOIN_TEST_GENESIS_HASH="4966625a4b2851d9fdee139e56211a0d88575f59ed816ff5e6a63deb4e3e29a0"
LITECOIN_REGTEST_GENESIS_HASH="530827f38f93b43ed12af0b3ad25a288dc02ed74d6d7857862df51fc56c416f9"
MINIMUM_CHAIN_WORK_MAIN="0x000000000000000000000000000000000000000000000006805c7318ce2736c0"
MINIMUM_CHAIN_WORK_TEST="0x000000000000000000000000000000000000000000000000000000054cb9e7a0"
COIN_NAME_LOWER="$(printf "%s\\n" "${COIN_NAME}" | tr '[:upper:]' '[:lower:]')"
COIN_NAME_UPPER="$(printf "%s\\n" "${COIN_NAME}" | tr '[:lower:]' '[:upper:]')"
CURRENT_DIR="$(cd "$(dirname "${0}")" && pwd)"
COIN_DIR="${CURRENT_DIR}/${COIN_NAME_LOWER}"
DOCKER_NETWORK="172.18.0"
DOCKER_IMAGE_LABEL="${COIN_NAME_LOWER}"
OSVERSION="$(uname -s)"
SECS="15"

set -e #exit on error

printfl()
{
    _printfl__max_len="$(stty size | awk '{print $2; exit}' 2>/dev/null)" || _printfl__max_len="80"
    if [ -n "${1}" ]; then
        _printfl__word_len="$((${#1} + 2))"
        _printfl__sub="$((_printfl__max_len - _printfl__word_len))"
        _printfl__half="$((_printfl__sub / 2))"
        _printfl__other_half="$((_printfl__sub - _printfl__half))"
        printf "%b" "\\033[1m" #white strong
        printf '%*s' "${_printfl__half}" '' | tr ' ' -
        printf "%b" "\\033[7m" #white background
        printf " %s " "${1}"
        printf "%b" "\\033[0m\\033[1m" #white strong
        printf '%*s' "${_printfl__other_half}" '' | tr ' ' -
        printf "%b" "\\033[0m" #back to normal
        printf "\\n"
    else
        printf "%b" "\\033[1m" #white strong
        printf '%*s' "${_printfl__max_len}" '' | tr ' ' -
        printf "%b" "\\033[0m" #back to normal
        printf "\\n"
    fi
}

printfs()
{
    [ -z "${1}" ] && return 1
    printf "%b\\n" "\\033[1m>>>> ${*}\\033[0m"
}

cmd()
{
    [ -z "${1}" ] && return 1
    printf "%s\\n" "[$] $*"
    #LAST_CMD="${*}"
    "$@"
}

printfv()
{
    [ -z "${1}" ] && return 1
    printf "%b\\n" "\\033[1m ${1}\\033[0m ${2}"
}

header()
{
    clear
    printfl "Altcoin Generator"
    printf "\\n"
    printfv "Updates:" "https://github.com/tiagosh/AltcoinGenerator"
    printf "\\n"
    printf "%s\\n" "Current configuration (edit the script to change it):"
    printf "\\n"
    printfv "Coin Name     :" "${COIN_NAME} / ${COIN_UNIT}"
    printfv "Total Supply  :" "${TOTAL_SUPPLY}"
    printfv "Premined coins:" "${PREMINED_AMOUNT:-none}"
    printfv "Base Maturity :" "${COINBASE_MATURITY}"
    printfv "Main NET Port :" "${MAINNET_PORT}"
    printfv "Test NET Port :" "${TESTNET_PORT}"
    printfv "Default Chain :" "${CHAIN:-main}"
    printfv "Client Version:" "${CLIENT_VERSION} / Copyright $(date +%Y)"
    printfv "Genesis Reward PubKey:" "${GENESIS_REWARD_PUBKEY}"
    printf "\\n"
    printf "%s" "Continuing in ${SECS} seconds, press Ctrl-c to cancel the operation ..."
    #sleep "${SECS}"
    printf "\\n"
}

footer()
{
    printfl "DONE"
    printf  "%s\\n" "Docker containers should be up and running now."
    printf  "%s\\n" "You may run the following command to check the network status:"
    printf  "\\n"
    printf  "%s\\n" "  [$] for i in \$(docker ps -q -f ancestor=${DOCKER_IMAGE_LABEL}); do docker exec \$i /${COIN_NAME_LOWER}/src/${COIN_NAME_LOWER}-cli ${CHAIN} getinfo; done"
    printf  "\\n"
    printf  "%s\\n" "To ask the nodes to mine some blocks simply run:"
    printf  "\\n"
    printf  "%s\\n" "  [$] for i in \$(docker ps -q -f ancestor=${DOCKER_IMAGE_LABEL}); do docker exec \$i /${COIN_NAME_LOWER}/src/${COIN_NAME_LOWER}-cli ${CHAIN} generate 2  & done"
}

docker_build_image()
{
    printfl "Building Docker Image"
    IMAGE="$(docker images -q "${DOCKER_IMAGE_LABEL}")"
    if [ -z "${IMAGE}" ]; then
        if [ ! -f "${COIN_DIR}/Dockerfile" ]; then
            printfs "Generating ${COIN_NAME_LOWER} environment ..."
            mkdir -p    "${COIN_DIR}"
            printfs "Creating ${COIN_DIR}/Dockerfile ..."
            cat <<EOF > "${COIN_DIR}/Dockerfile"
FROM ubuntu:16.04
RUN echo deb http://ppa.launchpad.net/bitcoin/bitcoin/ubuntu xenial main >> /etc/apt/sources.list
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv D46F45428842CE5E
RUN apt-get update && \
    apt-get -y install ccache git libboost-system1.58.0 libboost-filesystem1.58.0 libboost-program-options1.58.0 libboost-thread1.58.0 libboost-chrono1.58.0 libssl1.0.0 libevent-pthreads-2.0-5 libevent-2.0-5 build-essential libtool autotools-dev automake pkg-config libssl-dev libevent-dev bsdmainutils libboost-system-dev libboost-filesystem-dev libboost-chrono-dev libboost-program-options-dev libboost-test-dev libboost-thread-dev libdb4.8-dev libdb4.8++-dev libminiupnpc-dev libzmq3-dev libqt5gui5 libqt5core5a libqt5dbus5 qttools5-dev qttools5-dev-tools libprotobuf-dev protobuf-compiler libqrencode-dev python-pip
RUN pip install construct==2.5.2 scrypt
EOF
        else
            printfs "File ${COIN_DIR}/Dockerfile already exists, skipping ..."
        fi
        cmd docker build --label "${DOCKER_IMAGE_LABEL}" --tag "${DOCKER_IMAGE_LABEL}" "${COIN_DIR}/"
    else
        printfs "Docker image already built: '${DOCKER_IMAGE_LABEL}'"
    fi
}

docker_run_genesis()
{
    cmd mkdir -p "${COIN_DIR}/.ccache"
    cmd docker run -v "${COIN_DIR}/GenesisH0:/GenesisH0" "${DOCKER_IMAGE_LABEL}" /bin/bash -c "${1}"
}

docker_run()
{
    mkdir -p "${COIN_DIR}/.ccache"
    cmd docker run -v "${COIN_DIR}/GenesisH0:/GenesisH0" -v "${COIN_DIR}/.ccache:/root/.ccache" -v "${COIN_DIR}/${COIN_NAME_LOWER}:/${COIN_NAME_LOWER}" "${DOCKER_IMAGE_LABEL}" /bin/bash -c "${1}"
}

docker_stop_nodes()
{
    printfs "Stopping all docker nodes: '${DOCKER_IMAGE_LABEL}'"
    for id in $(docker ps -q -a -f ancestor="${DOCKER_IMAGE_LABEL}"); do
        cmd docker stop "${id}"
    done
}

docker_remove_nodes()
{
    printfs "Removing all docker nodes: '${DOCKER_IMAGE_LABEL}'"
    for id in $(docker ps -q -a -f ancestor="${DOCKER_IMAGE_LABEL}"); do
        cmd docker rm "${id}"
    done
}

docker_create_network()
{
    if ! docker network inspect "${DOCKER_IMAGE_LABEL}-network" >/dev/null 2>&1; then
        printfs  "Creating docker network: '${DOCKER_IMAGE_LABEL}-network'"
        cmd docker network create --subnet="${DOCKER_NETWORK}.0/16" "${DOCKER_IMAGE_LABEL}-network"
    else
        printfs  "Docker network '${DOCKER_IMAGE_LABEL}-network' already exists, skipping ..."
    fi
}

docker_remove_network()
{
    printfs "Removing docker network"
    cmd docker network rm "${DOCKER_IMAGE_LABEL}-network"
}

docker_run_node()
{
    unset NODE_NUMBER;  NODE_NUMBER="${1}"
    unset NODE_COMMAND; NODE_COMMAND="${2}"
    mkdir -p  "${COIN_DIR}/miner-${NODE_NUMBER}"
    if [ ! -f "${COIN_DIR}/miner-${NODE_NUMBER}/${COIN_NAME_LOWER}.conf" ]; then
        cat <<EOF > "${COIN_DIR}/miner-${NODE_NUMBER}/${COIN_NAME_LOWER}.conf"
rpcuser=${COIN_NAME_LOWER}rpc
rpcpassword=$(env LC_CTYPE=C tr -dc a-zA-Z0-9 < /dev/urandom| head -c 32; echo)
EOF
    fi

    cmd docker run --net "${DOCKER_IMAGE_LABEL}-network" --ip "${DOCKER_NETWORK}.${NODE_NUMBER}" -v "${COIN_DIR}/miner-${NODE_NUMBER}:/root/.${COIN_NAME_LOWER}" -v "${COIN_DIR}/${COIN_NAME_LOWER}:/${COIN_NAME_LOWER}" "${DOCKER_IMAGE_LABEL}" /bin/bash -c "${NODE_COMMAND}"
}

docker_run_nodes()
{
    printfs "Running miner docker nodes"
    docker_run_node 2 "cd /${COIN_NAME_LOWER} ; ./src/${COIN_NAME_LOWER}d ${CHAIN} -listen -noconnect -bind=${DOCKER_NETWORK}.2 -addnode=${DOCKER_NETWORK}.1 -addnode=${DOCKER_NETWORK}.3 -addnode=${DOCKER_NETWORK}.4 -addnode=${DOCKER_NETWORK}.5" &
    docker_run_node 3 "cd /${COIN_NAME_LOWER} ; ./src/${COIN_NAME_LOWER}d ${CHAIN} -listen -noconnect -bind=${DOCKER_NETWORK}.3 -addnode=${DOCKER_NETWORK}.1 -addnode=${DOCKER_NETWORK}.2 -addnode=${DOCKER_NETWORK}.4 -addnode=${DOCKER_NETWORK}.5" &
    docker_run_node 4 "cd /${COIN_NAME_LOWER} ; ./src/${COIN_NAME_LOWER}d ${CHAIN} -listen -noconnect -bind=${DOCKER_NETWORK}.4 -addnode=${DOCKER_NETWORK}.1 -addnode=${DOCKER_NETWORK}.2 -addnode=${DOCKER_NETWORK}.3 -addnode=${DOCKER_NETWORK}.5" &
    docker_run_node 5 "cd /${COIN_NAME_LOWER} ; ./src/${COIN_NAME_LOWER}d ${CHAIN} -listen -noconnect -bind=${DOCKER_NETWORK}.5 -addnode=${DOCKER_NETWORK}.1 -addnode=${DOCKER_NETWORK}.2 -addnode=${DOCKER_NETWORK}.3 -addnode=${DOCKER_NETWORK}.4" &
}

generate_genesis_block()
{
    printfl "Generating Genesis Blocks"
    mkdir -p "${COIN_DIR}"
    if [ ! -d "${COIN_DIR}/GenesisH0" ]; then
        (
            cd "${COIN_DIR}"
            printfs "Cloning GenesisH0 repository ..."
            cmd git clone "${GENESISHZERO_REPOS}" "${COIN_DIR}/GenesisH0"
        )
    else
        (
            cd "${COIN_DIR}"
            printfs "Updating GenesisH0 repository ..."
            cmd git pull
        )
    fi

    if [ ! -f "${COIN_DIR}/GenesisH0/${COIN_NAME}-main.txt" ]; then
        printfs "Mining main network genesis block ... this procedure can take many hours of cpu work ..."
        docker_run_genesis "python /GenesisH0/genesis.py -a scrypt -z '${PHRASE}' -p ${GENESIS_REWARD_PUBKEY} 2>&1 | tee /GenesisH0/${COIN_NAME}-main.txt"
    else
        printfs "Genesis main block already mined ..."
        cmd cat "${COIN_DIR}/GenesisH0/${COIN_NAME}-main.txt"
    fi

    if [ ! -f "${COIN_DIR}/GenesisH0/${COIN_NAME}-test.txt" ]; then
        printfs "Mining test network genesis ... this procedure can take many hours of cpu work ..."
        docker_run_genesis "python /GenesisH0/genesis.py  -t 1486949366 -a scrypt -z '${PHRASE}' -p ${GENESIS_REWARD_PUBKEY} 2>&1 | tee /GenesisH0/${COIN_NAME}-test.txt"
    else
        printfs "Genesis test block already mined ..."
        cmd cat "${COIN_DIR}/GenesisH0/${COIN_NAME}-test.txt"
    fi

    if [ ! -f "${COIN_DIR}/GenesisH0/${COIN_NAME}-regtest.txt" ]; then
        printfs "Mining regtest genesis block ... this procedure can take many hours of cpu work ..."
        docker_run_genesis "python /GenesisH0/genesis.py -t 1296688602 -b 0x207fffff -n 0 -a scrypt -z '${PHRASE}' -p $GENESIS_REWARD_PUBKEY 2>&1 | tee /GenesisH0/${COIN_NAME}-regtest.txt"
    else
        printfs "Genesis regtest block already mined ..."
        cmd cat "${COIN_DIR}/GenesisH0/${COIN_NAME}-regtest.txt"
    fi

    MAIN_PUB_KEY="$(awk '/^pubkey:/{print $2; exit}'     "${COIN_DIR}/GenesisH0/${COIN_NAME}-main.txt")"
    MERKLE_HASH="$(awk '/^merkle hash:/{print $3; exit}' "${COIN_DIR}/GenesisH0/${COIN_NAME}-main.txt")"
    TIMESTAMP="$(awk '/^time:/{print $2; exit}'          "${COIN_DIR}/GenesisH0/${COIN_NAME}-main.txt")"
    BITS="$(awk '/^bits:/{print $2; exit}'               "${COIN_DIR}/GenesisH0/${COIN_NAME}-main.txt")"

    MAIN_NONCE="$(awk '/^nonce:/{print $2; exit}'    "${COIN_DIR}/GenesisH0/${COIN_NAME}-main.txt")"
    TEST_NONCE="$(awk '/^nonce:/{print $2; exit}'    "${COIN_DIR}/GenesisH0/${COIN_NAME}-test.txt")"
    REGTEST_NONCE="$(awk '/^nonce:/{print $2; exit}' "${COIN_DIR}/GenesisH0/${COIN_NAME}-regtest.txt")"

    MAIN_GENESIS_HASH="$(awk '/^genesis hash:/{print $3; exit}'    "${COIN_DIR}/GenesisH0/${COIN_NAME}-main.txt")"
    TEST_GENESIS_HASH="$(awk '/^genesis hash:/{print $3; exit}'    "${COIN_DIR}/GenesisH0/${COIN_NAME}-test.txt")"
    REGTEST_GENESIS_HASH="$(awk '/^genesis hash:/{print $3; exit}' "${COIN_DIR}/GenesisH0/${COIN_NAME}-regtest.txt")"
}

newcoin_replace_vars()
{
    printfl "Forking '${COIN_NAME_LOWER}' coin"
    mkdir  -p "${COIN_DIR}"
    if [ -d "${COIN_DIR}/${COIN_NAME_LOWER}" ]; then
        printfs "Warning: ${COIN_DIR}/${COIN_NAME_LOWER} already exists. Not replacing any values"
        return 0
    fi
    if [ ! -d "${COIN_DIR}/litecoin-master" ]; then
        (
            cd "${COIN_DIR}"
            printfs "Cloning base cryptocurrency ..."
            # clone litecoin and keep local cache
            cmd git clone -b "${LITECOIN_BRANCH}" "${LITECOIN_REPOS}" litecoin-master
        )
    else
        (
            cd "${COIN_DIR}/litecoin-master"
            printfs "Updating master branch ..."
            cmd git pull
        )
    fi

    (
        cd "${COIN_DIR}"
        printfs "Forking to '${COIN_NAME_LOWER}' directory ..."
        cmd git clone -b "${LITECOIN_BRANCH}" litecoin-master "${COIN_NAME_LOWER}"

        cd "${COIN_NAME_LOWER}"

        # first rename all directories
        printfs "Renaming files ..."
        for i in $(find . -type d | grep -v "^./.git" | grep litecoin); do
            cmd git mv "${i}" "$(printf "%s\\n" "${i}"| $SED "s/litecoin/${COIN_NAME_LOWER}/")"
        done

        # then rename all files
        for i in $(find . -type f | grep -v "^./.git" | grep litecoin); do
            cmd git mv "${i}" "$(printf "%s\\n" "${i}"| $SED "s/litecoin/${COIN_NAME_LOWER}/")"
        done

        # now replace all litecoin references to the new coin name
        for i in $(find . -type f | grep -v "^./.git"); do
            [ -z "${replace_coin_title}" ] && printfs "Replacing coin name 'litecoin' => '${COIN_NAME_LOWER}'" && replace_coin_title=1
            # ommit too verbose information
            "${SED}" -i "s/Litecoin/${COIN_NAME}/g" "${i}"
            "${SED}" -i "s/litecoin/${COIN_NAME_LOWER}/g" "${i}"
            "${SED}" -i "s/LITECOIN/${COIN_NAME_UPPER}/g" "${i}"
            "${SED}" -i "s/LTC/${COIN_UNIT}/g" "${i}"
        done

        printfs "Setting up total supply => ${TOTAL_SUPPLY} coins"
        cmd "${SED}" -i "s/84000000/${TOTAL_SUPPLY}/" src/amount.h

        printfs "Setting up genesis block phrase => '${PHRASE}'"
        cmd "${SED}" -i "s;NY Times 05/Oct/2011 Steve Jobs, Apple’s Visionary, Dies at 56;${PHRASE};" src/chainparams.cpp
        cmd "${SED}" -i "s/1,48/1,${PUBKEY_CHAR}/"    src/chainparams.cpp
        cmd "${SED}" -i "s/1317972665/${TIMESTAMP}/"  src/chainparams.cpp

        printfs "Setting up main net port => '${MAINNET_PORT}'"
        cmd "${SED}" -i "s/= 9333;/= ${MAINNET_PORT};/"  src/chainparams.cpp
        printfs "Setting up test net port => '${TESTNET_PORT}'"
        cmd "${SED}" -i "s/= 19335;/= ${TESTNET_PORT};/" src/chainparams.cpp

        printfs "Setting up default genesis / markle hashes"
        cmd "${SED}" -i "s/${LITECOIN_PUB_KEY}/${MAIN_PUB_KEY}/"    src/chainparams.cpp
        cmd "${SED}" -i "s/${LITECOIN_MERKLE_HASH}/${MERKLE_HASH}/" src/chainparams.cpp
        cmd "${SED}" -i "s/${LITECOIN_MERKLE_HASH}/${MERKLE_HASH}/" src/qt/test/rpcnestedtests.cpp

        cmd "${SED}" -i "0,/${LITECOIN_MAIN_GENESIS_HASH}/s//${MAIN_GENESIS_HASH}/"       src/chainparams.cpp
        cmd "${SED}" -i "0,/${LITECOIN_TEST_GENESIS_HASH}/s//${TEST_GENESIS_HASH}/"       src/chainparams.cpp
        cmd "${SED}" -i "0,/${LITECOIN_REGTEST_GENESIS_HASH}/s//${REGTEST_GENESIS_HASH}/" src/chainparams.cpp

        cmd "${SED}" -i "0,/2084524493/s//${MAIN_NONCE}/"                   src/chainparams.cpp
        cmd "${SED}" -i "0,/293345/s//${TEST_NONCE}/"                       src/chainparams.cpp
        cmd "${SED}" -i "0,/1296688602, 0/s//1296688602, ${REGTEST_NONCE}/" src/chainparams.cpp
        cmd "${SED}" -i "0,/0x1e0ffff0/s//${BITS}/"                         src/chainparams.cpp

        printfs "Commenting out external seeds"
        cmd "${SED}" -i "s,vSeeds.push_back,//vSeeds.push_back,g" src/chainparams.cpp

        if [ -n "${PREMINED_AMOUNT}" ]; then
            printfs "Setting up default premined coins for 1st block => '${PREMINED_AMOUNT}' coins"
            cmd "${SED}" -i "s/CAmount nSubsidy = 50 \\* COIN;/if \\(nHeight == 1\\) return COIN \\* ${PREMINED_AMOUNT};\\n    CAmount nSubsidy = 50 \\* COIN;/" src/validation.cpp
        fi

        printfs "Setting up coin madurity => '${COINBASE_MATURITY}'"
        cmd "${SED}" -i "s/COINBASE_MATURITY = 100/COINBASE_MATURITY = ${COINBASE_MATURITY}/" src/consensus/consensus.h

        printfs "Resetting minimum chain work => '0'"
        cmd "${SED}" -i "s/${MINIMUM_CHAIN_WORK_MAIN}/0x00/" src/chainparams.cpp
        cmd "${SED}" -i "s/${MINIMUM_CHAIN_WORK_TEST}/0x00/" src/chainparams.cpp

        printfs "Resetting bip activation heights => '0'"
        # bip 34
        cmd "${SED}" -i "s/710000/0/" src/chainparams.cpp
        # bip 65
        cmd "${SED}" -i "s/918684/0/" src/chainparams.cpp
        # bip 66
        cmd "${SED}" -i "s/811879/0/" src/chainparams.cpp

        printfs "Resetting checkpoints"
        cmd "${SED}" -i -n -e "/boost::assign::map_list_of/{" -e "p" -e ":a" -e "N" -e "/};/!ba" -e "s/.*\n//" -e "}" -e "p" src/chainparams.cpp
        cmd "${SED}" -i '/boost::assign::map_list_of/a\            (0, uint256S("0x"))' src/chainparams.cpp
        cmd "${SED}" -i -n -e "/chainTxData = ChainTxData/{" -e "p" -e ":a" -e "N" -e "/};/!ba" -e "s/.*\n//" -e "}" -e "p"  src/chainparams.cpp
        cmd "${SED}" -i '/chainTxData = ChainTxData/a\            0,0,0' src/chainparams.cpp
        #if PREMINED_AMOUNT > 0 checkpoints should point to those first block
        #https://vcoin-project.github.io/cloning-litecoin/ => Checkpointing the premine.

        printfs "Setting client version => '${CLIENT_VERSION}'"
        CLIENT_VERSION_MAJOR="$(printf "%s\\n" "${CLIENT_VERSION}"    | cut -d. -f1)"
        CLIENT_VERSION_MINOR="$(printf "%s\\n" "${CLIENT_VERSION}"    | cut -d. -f2)"
        CLIENT_VERSION_REVISION="$(printf "%s\\n" "${CLIENT_VERSION}" | cut -d. -f3)"
        CLIENT_VERSION_BUILD="$(printf "%s\\n" "${CLIENT_VERSION}"    | cut -d. -f4)"
        cmd "${SED}" -i "s/define(_CLIENT_VERSION_MAJOR.*/define\\(_CLIENT_VERSION_MAJOR, ${CLIENT_VERSION_MAJOR}\\)/" configure.ac
        cmd "${SED}" -i "s/define(_CLIENT_VERSION_MINOR.*/define\\(_CLIENT_VERSION_MINOR, ${CLIENT_VERSION_MINOR}\\)/" configure.ac
        cmd "${SED}" -i "s/define(_CLIENT_VERSION_REVISION.*/define\\(_CLIENT_VERSION_REVISION, ${CLIENT_VERSION_REVISION}\\)/" configure.ac
        cmd "${SED}" -i "s/define(_CLIENT_VERSION_BUILD.*/define\\(_CLIENT_VERSION_BUILD, ${CLIENT_VERSION_BUILD}\\)/" configure.ac
        cmd "${SED}" -i "s/define(_COPYRIGHT_YEAR,.*/define\\(_COPYRIGHT_YEAR, $(date +%Y)\\)/" configure.ac
    )
}

build_new_coin()
{
    printfs "Building '${COIN_NAME_LOWER}' coin"
    # only run autogen.sh/configure if not done previously
    if [ ! -e "${COIN_DIR}/${COIN_NAME_LOWER}/Makefile" ]; then
        docker_run "cd /${COIN_NAME_LOWER} ; bash /${COIN_NAME_LOWER}/autogen.sh"
        docker_run "cd /${COIN_NAME_LOWER} ; bash /${COIN_NAME_LOWER}/configure"
    fi
    # always build as the user could have manually changed some files
    docker_run "cd /${COIN_NAME_LOWER} ; make -j2"
}

progname="$(basename "${0}")"

# sanity check
case "${OSVERSION}" in
    Linux*)
        SED="$(command -v "sed" 2>/dev/null)"
    ;;
    Darwin*)
        if ! command -v "gsed" >/dev/null 2>&1; then
            echo "Please install gnu-sed with 'brew install gnu-sed'"
            exit 1
        fi
        SED="$(command -v "gsed" 2>/dev/null)"
    ;;
    *)
        echo "This script only works on Linux and MacOS"
        exit 1
    ;;
esac

if ! command -v "docker" >/dev/null 2>&1; then
    echo "Please install docker first"
    exit 1
fi

if ! command -v "git" >/dev/null 2>&1; then
    echo "Please install git first"
    exit 1
fi

case "$(printf "%s\\n" "${1}" | tr '[:upper:]' '[:lower:]')" in
    sto*)
        docker_stop_nodes
    ;;
    r*)
        docker_stop_nodes
        docker_remove_nodes
    ;;
    c*)
        docker_stop_nodes
        for i in $(seq 2 5); do
           docker_run_node "${i}" "rm -rf /${COIN_NAME_LOWER} /root/.${COIN_NAME_LOWER}" >/dev/null 2>&1
        done
        docker_remove_nodes
        docker_remove_network
        rm -rf "${COIN_NAME_LOWER}"
        if [ "${2}" != "keep_genesis_block" ]; then
            rm -f "GenesisH0/${COIN_NAME}"-*.txt
        fi
        for i in $(seq 2 5); do
           rm -rf "miner-${i}"
        done
    ;;
    sta*)
        if [ -n "$(docker ps -q -f ancestor="${DOCKER_IMAGE_LABEL}")" ]; then
            echo "There are nodes running. Please stop them first with: ${progname} stop"
            exit 1
        fi

        header
        docker_build_image
        generate_genesis_block
        newcoin_replace_vars
        build_new_coin
        docker_create_network
        docker_run_nodes; sleep 3
        footer
    ;;
    *)
        cat <<EOF
Usage: ${progname} (start|stop|remove_nodes|clean_up)
 - start: bootstrap environment, build and run your new coin
 - stop: simply stop the containers without removing them
 - remove_nodes: remove the old docker container images. This will stop them first if necessary.
 - clean_up: WARNING: this will stop and remove docker containers and network, source code, genesis block information and nodes data directory. (to start from scratch)
EOF
    ;;
esac
