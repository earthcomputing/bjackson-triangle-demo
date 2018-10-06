#!/bin/sh
# usage: $0 <machineName>

nodejs eccf-server.js &
sleep 3
./adapter $1
