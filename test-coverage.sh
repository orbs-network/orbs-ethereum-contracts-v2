#!/bin/bash -xe
mkdir -p _out
npm install
sleep 5 # give ganache some time to start
yarn coverage

