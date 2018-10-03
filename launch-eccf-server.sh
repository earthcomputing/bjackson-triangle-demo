#!/bin/sh
# usage: $0 <machineName>

node eccf-server.js &
sleep 3
./adapter $1
