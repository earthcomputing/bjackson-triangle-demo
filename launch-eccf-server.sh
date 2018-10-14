#!/bin/sh
# usage: $0 <machineName>

exit 1 unless $1

nodejs eccf-server.js $1 &
sleep 3
./adapter $1
