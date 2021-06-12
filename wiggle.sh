#!/bin/csh -f
#---------------------------------------------------------------------------------------------
 #  Copyright © 2016-present Earth Computing Corporation. All rights reserved.
 #  Licensed under the MIT License. See LICENSE.txt in the project root for license information.
#---------------------------------------------------------------------------------------------

set alice = 172.16.1.67
set bob = 172.16.1.40
set carol = 172.16.1.105

set body = 'sudo ifconfig enp6s0 down ; sudo ifconfig enp6s0 up ; sudo ifconfig enp7s0 down ; sudo ifconfig enp7s0 up ; sudo ifconfig enp8s0 down ; sudo ifconfig enp8s0 up ; sudo ifconfig enp9s0 down ; sudo ifconfig enp9s0 up'

foreach one ( ${alice} ${bob} ${carol} )
    ssh -t demouser@${one} "${body}"
end

