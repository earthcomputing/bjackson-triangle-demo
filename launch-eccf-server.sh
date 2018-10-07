#!/bin/sh
# usage: $0 <machineName>

nodejs eccf-server.js $1 &
sleep 3
./adapter $1
