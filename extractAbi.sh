#!/bin/bash -e
rm -rf ./abi
mkdir -p ./abi

for full_filename in build/contracts/*.json; do
    filename=`basename $full_filename`
    script="console.log(JSON.stringify(JSON.parse(require('fs').readFileSync('./${full_filename}').toString()).abi,null,2))"
    shortName=`echo ${filename} | rev | cut -d"." -f2-  | rev`
    echo $script | node >  ./abi/${shortName}.abi.json
done
