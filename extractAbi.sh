#!/bin/bash -e
rm -rf ./release/abi
mkdir -p ./release/abi
for full_filename in build/contracts/*.json; do
    filename=`basename $full_filename`
    ./node_modules/node-jq/bin/jq '.abi' ${full_filename} > ./release/abi/${filename}.abi.json
done
