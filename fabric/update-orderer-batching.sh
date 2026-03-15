#!/bin/bash
set -euo pipefail

cd ~/secdt-fabric

export PATH=$PATH:~/bin:/usr/local/go/bin
export FABRIC_CFG_PATH=$HOME/config
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=OrdererMSP
export CORE_PEER_MSPCONFIGPATH=$HOME/secdt-fabric/crypto-config/ordererOrganizations/secdt.com/users/Admin@secdt.com/msp
export ORDERER_CA=$HOME/secdt-fabric/crypto-config/ordererOrganizations/secdt.com/orderers/orderer-fabric-1.secdt.com/tls/ca.crt

CHANNEL_NAME=secdt-channel

rm -f config_block.pb config_block.json config.json modified_config.json config.pb modified_config.pb config_update.pb config_update.json config_update_in_envelope.json config_update_in_envelope.pb

peer channel fetch config config_block.pb -o orderer-fabric-1:7050 -c "$CHANNEL_NAME" --tls --cafile "$ORDERER_CA"

configtxlator proto_decode --input config_block.pb --type common.Block > config_block.json
jq '.data.data[0].payload.data.config' config_block.json > config.json

jq '
.channel_group.groups.Orderer.values.BatchTimeout.value.timeout = "500ms" |
.channel_group.groups.Orderer.values.BatchSize.value.max_message_count = 10000 |
.channel_group.groups.Orderer.values.BatchSize.value.preferred_max_bytes = 50331648
' config.json > modified_config.json

configtxlator proto_encode --input config.json --type common.Config > config.pb
configtxlator proto_encode --input modified_config.json --type common.Config > modified_config.pb
configtxlator compute_update --channel_id "$CHANNEL_NAME" --original config.pb --updated modified_config.pb > config_update.pb
configtxlator proto_decode --input config_update.pb --type common.ConfigUpdate > config_update.json

echo '{"payload":{"header":{"channel_header":{"channel_id":"'"$CHANNEL_NAME"'","type":2}},"data":{"config_update":'$(cat config_update.json)'}}}' | jq . > config_update_in_envelope.json

configtxlator proto_encode --input config_update_in_envelope.json --type common.Envelope > config_update_in_envelope.pb

peer channel update -f config_update_in_envelope.pb -c "$CHANNEL_NAME" -o orderer-fabric-1:7050 --tls --cafile "$ORDERER_CA"

sleep 3

peer channel fetch config config_block.pb -o orderer-fabric-1:7050 -c "$CHANNEL_NAME" --tls --cafile "$ORDERER_CA"

configtxlator proto_decode --input config_block.pb --type common.Block | jq '.data.data[0].payload.data.config.channel_group.groups.Orderer.values.BatchTimeout.value'
configtxlator proto_decode --input config_block.pb --type common.Block | jq '.data.data[0].payload.data.config.channel_group.groups.Orderer.values.BatchSize.value'
