#!/bin/sh
#---------------------------------------------------------------------------------------------
 #  Copyright © 2016-present Earth Computing Corporation. All rights reserved.
 #  Licensed under the MIT License. See LICENSE.txt in the project root for license information.
#---------------------------------------------------------------------------------------------
# usage: $0 <machineName>

exit 1 unless $1

nodejs eccf-server.js $1 &
sleep 3
./adapter $1
