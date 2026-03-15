#!/bin/bash
set -euo pipefail

cd ~/secdt-fabric

export PATH=$PATH:~/bin:/usr/local/go/bin
export FABRIC_CFG_PATH=$HOME/config
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=PeerMSP
export CORE_PEER_TLS_ROOTCERT_FILE=$HOME/secdt-fabric/crypto-config/peerOrganizations/secdt.com/peers/peer-fabric-1.secdt.com/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=$HOME/secdt-fabric/crypto-config/peerOrganizations/secdt.com/users/Admin@secdt.com/msp
export CORE_PEER_ADDRESS=peer-fabric-1:7051
export ORDERER_CA=$HOME/secdt-fabric/crypto-config/ordererOrganizations/secdt.com/orderers/orderer-fabric-1.secdt.com/tls/ca.crt

peer channel join -b ~/secdt-fabric/secdt-channel.block

peer lifecycle chaincode queryinstalled
peer lifecycle chaincode install ~/secdt-fabric/secdt.tar.gz
peer lifecycle chaincode queryinstalled

peer channel list
peer lifecycle chaincode querycommitted --channelID secdt-channel --name secdt

peer chaincode invoke \
  -o orderer-fabric-1:7050 \
  --tls --cafile $ORDERER_CA \
  -C secdt-channel \
  -n secdt \
  --peerAddresses peer-fabric-1:7051 \
  --tlsRootCertFiles $HOME/secdt-fabric/crypto-config/peerOrganizations/secdt.com/peers/peer-fabric-1.secdt.com/tls/ca.crt \
  -c '{"Args":["RegisterState","machine-001","QmSecDTTestCID001","87.5","120","session-001","hash-abc-123"]}'

sleep 3

peer chaincode query \
  -C secdt-channel \
  -n secdt \
  -c '{"Args":["VerifyIntegrity","machine-001","hash-abc-123"]}'

peer chaincode query \
  -C secdt-channel \
  -n secdt \
  -c '{"Args":["GetHistory","machine-001"]}'
