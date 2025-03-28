#!/bin/bash

EXPLORER_IMAGE=raininfotech14/blocx-beaconcha:latest
CONFIG_CHAIN_NAME=mainnet
CONFIG_CL_NODE_HOST=node-beacon-1
CONFIG_CL_NODE_PORT=5052
CONFIG_EL_NODE_HOST=node-execution-1
CONFIG_EL_NODE_PORT=8545
BIG_TABLE_HOST=lbt
BIG_TABLE_PORT=9000
POSTGRESS_HOST=postgres
POSTGRESS_PORT=5432
POSTGRESS_USER=user
POSTGRESS_PASSWORD=pass
POSTGRESS_DB=db
REDIS_HOST=redis
REDIS_PORT=6379
HOST_IP_ADDRESS=$(curl -4 -s https://icanhazip.com/)
# HOST_IP_ADDRESS=localhost
NETWORK_NAME="my-network"

# Check if the network exists
if ! docker network inspect "$NETWORK_NAME" > /dev/null 2>&1; then
    echo "Network '$NETWORK_NAME' does not exist. Creating network..."
    docker network create "$NETWORK_NAME"
else
    echo "Network '$NETWORK_NAME' already exists."
fi

# Check if the container is connected to the network
if ! docker inspect "$CONFIG_CL_NODE_HOST" | grep -q "$NETWORK_NAME"; then
    echo "Container '$CONFIG_CL_NODE_HOST' is not connected to '$NETWORK_NAME'. Connecting container..."
    docker network connect "$NETWORK_NAME" "$CONFIG_CL_NODE_HOST"
else
    echo "Container '$CONFIG_CL_NODE_HOST' is already connected to '$NETWORK_NAME'."
fi

if ! docker inspect "$CONFIG_EL_NODE_HOST" | grep -q "$NETWORK_NAME"; then
    echo "Container '$CONFIG_EL_NODE_HOST' is not connected to '$NETWORK_NAME'. Connecting container..."
    docker network connect "$NETWORK_NAME" "$CONFIG_EL_NODE_HOST"
else
    echo "Container '$CONFIG_EL_NODE_HOST' is already connected to '$NETWORK_NAME'."
fi



set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
cd $DIR

var_help="./run.sh <cmd> <options>

run.sh start  
run.sh stop   
"

fn_main() {
    if test $# -eq 0; then
        echo "$var_help"
        return
    fi
    while test $# -ne 0; do
        case $1 in
            start) shift; fn_start "$@"; exit;;
            stop) shift; fn_stop "$@"; exit;;
            *) echo "$var_help"
        esac
        shift
    done
}

fn_start() {
    # fn_stop
    fn_write_compose
    fn_write_config
    docker compose --profile=init run -T init
    docker compose up -d --remove-orphans
}

fn_stop() {
    cd $DIR
    docker compose down --remove-orphans
    sudo rm -rf config.yml compose.yml
    # sudo rm -rf volumes
}

fn_write_compose() {
    cat <<EOF > $DIR/compose.yml
x-services: &explorer-base
  image: $EXPLORER_IMAGE
  volumes:
    - ./config.yml:/v-config.yml
    - ./explorer-configs:/explorer-configs
services:
  ##################### init
  init:
    <<: *explorer-base
    profiles:
      - init
    depends_on:
      postgres:
        condition: service_healthy
      lbt:
        condition: service_started
      redis:
        condition: service_started
    command: |
      /bin/bash -c "
      ./misc -config /v-config.yml -command=applyDbSchema
      ./misc -config /v-config.yml -command=initBigtableSchema
      "
    networks:
      - $NETWORK_NAME

  ##################### dbs
  postgres:
    image: postgres:15
    restart: unless-stopped
    environment:
      - POSTGRES_DB=$POSTGRESS_DB
      - POSTGRES_USER=$POSTGRESS_USER
      - POSTGRES_PASSWORD=$POSTGRESS_PASSWORD
    volumes:
      - ./volumes/postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready", "-d", "$POSTGRESS_DB"]
      interval: 1s
      timeout: 1s
    networks:
      - $NETWORK_NAME
  lbt:
    image: gobitfly/little_bigtable:latest
    volumes:
      - ./volumes/lbt:/data
    networks:
      - $NETWORK_NAME
  redis:
    image: redis:7
    volumes:
      - ./volumes/redis:/data
    networks:
      - $NETWORK_NAME
  ##################### explorer
  indexer:
    <<: *explorer-base
    command: ./explorer -config /v-config.yml
    environment:
      - INDEXER_ENABLED=true
    networks:
      - $NETWORK_NAME
  eth1indexer:
    <<: *explorer-base
    command: ./eth1indexer -config /v-config.yml -blocks.tracemode 'geth' -data.concurrency 1 -data.start=0 -data.end=0 --balances.enabled 
    networks:
      - $NETWORK_NAME
  rewards-exporter:
    <<: *explorer-base
    command: ./rewards-exporter -config /v-config.yml 
    networks:
      - $NETWORK_NAME
  statistics:
    <<: *explorer-base
    command: ./statistics -config /v-config.yml --statistics.day -1 --charts.enabled --graffiti.enabled -validators.enabled
    networks:
      - $NETWORK_NAME
  frontend-data-updater:
    <<: *explorer-base
    command: ./frontend-data-updater -config /v-config.yml
    networks:
      - $NETWORK_NAME
  frontend:
    <<: *explorer-base
    command: ./explorer -config /v-config.yml
    environment:
      - INDEXER_ENABLED=true
      - FRONTEND_ENABLED=true
    ports:
      - 8080:8080
    networks:
      - $NETWORK_NAME
networks:
  $NETWORK_NAME:
    external: true
EOF
}

fn_write_config() {
    cat <<EOF > $DIR/config.yml
database:
  user: "$POSTGRESS_USER"
  name: "$POSTGRESS_DB"
  host: "$POSTGRESS_HOST"
  port: "$POSTGRESS_PORT"
  password: "$POSTGRESS_PASSWORD"
chain:
  name: testnet
  id: 9513
  clConfigPath: node
  elConfigPath: "/explorer-configs/network-params.json"
  configPath: "/explorer-configs/config.yaml"
  genesisTimestamp: 1741416415
  clConfig:
    configName: "testnet"
    slotsPerEpoch: 32
    secondsPerSlot: 3
    depositChainID: 9513
frontend:
  enabled: true # Enable or disable to web frontend
  debug: true
  # imprint: "./imprint.html"  
  siteDomain: "http://$HOST_IP_ADDRESS:8080"
  siteName: "BLOCX Explorer" 
  siteSubtitle: "BLOCX explorer" 
  csrfAuthKey: '0123456789abcdef000000000000000000000000000000000000000000000000'
  jwtSigningSecret: "0123456789abcdef000000000000000000000000000000000000000000000000"
  jwtIssuer: "localblockexplorer"
  jwtValidityInMinutes: 30
  sessionSecret: "11111111111111111111111111111111"
  # elCurrency: "ETH"
  # clCurrency: "ETH"
  # clCurrencyDivisor: 64
  # elCurrencyDivisor: 64
  mainCurrency: "ETH"
  slotViz:
    enabled: true
    hardforkEpoch: 0
  server:
    host: "0.0.0.0" 
    port: "8080" 
  database:
    user: "$POSTGRESS_USER"
    name: "$POSTGRESS_DB"
    host: "$POSTGRESS_HOST"
    port: "$POSTGRESS_PORT"
    password: "$POSTGRESS_PASSWORD"
  readerDatabase:
    user: "$POSTGRESS_USER"
    name: "$POSTGRESS_DB"
    host: "$POSTGRESS_HOST"
    port: "$POSTGRESS_PORT"
    password: "$POSTGRESS_PASSWORD"
  writerDatabase:
    user: "$POSTGRESS_USER"
    name: "$POSTGRESS_DB"
    host: "$POSTGRESS_HOST"
    port: "$POSTGRESS_PORT"
    password: "$POSTGRESS_PASSWORD"

readerDatabase:
  user: "$POSTGRESS_USER"
  name: "$POSTGRESS_DB"
  host: "$POSTGRESS_HOST"
  port: "$POSTGRESS_PORT"
  password: "$POSTGRESS_PASSWORD"
writerDatabase:
  user: "$POSTGRESS_USER"
  name: "$POSTGRESS_DB"
  host: "$POSTGRESS_HOST"
  port: "$POSTGRESS_PORT"
  password: "$POSTGRESS_PASSWORD"
bigtable:
  project: explorer
  instance: explorer
  emulator: true
  emulatorHost: $BIG_TABLE_HOST
  emulatorPort: $BIG_TABLE_PORT
indexer:
  enabled: true 
  indexMissingEpochsOnStartup: true 
  node:
    host: "$CONFIG_CL_NODE_HOST" 
    port: "$CONFIG_CL_NODE_PORT" 
    type: "lighthouse" 
    pageSize: 100 
  eth1Endpoint: 'http://$CONFIG_EL_NODE_HOST:$CONFIG_EL_NODE_PORT'
  eth1DepositContractFirstBlock: 0
eth1ErigonEndpoint: http://$CONFIG_EL_NODE_HOST:$CONFIG_EL_NODE_PORT
eth1GethEndpoint: http://$CONFIG_EL_NODE_HOST:$CONFIG_EL_NODE_PORT
redisCacheEndpoint: '$REDIS_HOST:$REDIS_PORT'
redisSessionStoreEndpoint: '$REDIS_HOST:$REDIS_PORT'
tieredCacheProvider: 'redis'
monitoring:
  enabled: true
  serviceMonitoringConfigurations:
    - name: "eth1indexer"
      duration: 1s
    - name: "latestProposedSlotUpdater"
      duration: 1s
    - name: "epochUpdater"
      duration: 1s
    - name: "rewardsExporter"
      duration: 1s
    - name: "mempoolUpdater"
      duration: 1s
    - name: "indexPageDataUpdater"
      duration: 1s
    - name: "latestBlockUpdater"
      duration: 1s
    - name: "headBlockRootHashUpdater"
      duration: 1s
    - name: "relaysUpdater"
      duration: 1s
    - name: "ethstoreExporter"
      duration: 1s
    - name: "statsUpdater"
      duration: 1s
    - name: "slotExporter"
      duration: 1s
    - name: "statistics"
      duration: 1s
    - name: "lastExportedStatisticDay"
      duration: 1s
    - name: "slotVizUpdater"
      duration: 1s
    - name: "slotUpdater"
      duration: 1s
    - name: "ethStoreStatistics"
      duration: 1s


ratelimitUpdater:
  enabled: true
  updateInterval: 5s
EOF
}

fn_main "$@"