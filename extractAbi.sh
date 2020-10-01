#!/bin/bash -e
rm -rf ./release/abi
mkdir -p ./release/abi

for full_filename in build/contracts/*.json; do
    filename=`basename $full_filename`
    script="console.log(JSON.stringify(JSON.parse(require('fs').readFileSync('./${full_filename}').toString()).abi,null,2))"
    shortName=`echo ${filename} | rev | cut -d"." -f2-  | rev`
    echo $script | node >  ./release/abi/${shortName}.abi
done
