#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT=${DIR}/../flat/

declare -a CONTRACTS=(
    "Certification"
    "Committee"
    "ContractRegistry"
    "Delegations"
    "Elections"
    "FeesAndBootstrapRewards"
    "FeesWallet"
    "GuardiansRegistration"
    "Lockable"
    "Protocol"
    "ProtocolWallet"
    "StakingContractHandler"
    "StakingRewards"
    "Subscriptions"
)

mkdir -p ${OUTPUT}

for contract in "${CONTRACTS[@]}"
do
    ../node_modules/.bin/truffle-flattener ${DIR}/../contracts/${contract}.sol > ${OUTPUT}/${contract}.sol
done