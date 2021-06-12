#!/bin/csh -f
#---------------------------------------------------------------------------------------------
 #  Copyright © 2016-present Earth Computing Corporation. All rights reserved.
 #  Licensed under the MIT License. See LICENSE.txt in the project root for license information.
#---------------------------------------------------------------------------------------------

set alice = 172.16.1.67
set bob = 172.16.1.40
set carol = 172.16.1.105

# set USER_NAME = `git config user.email`
# env GIT_AUTHOR_EMAIL=${USER_NAME} 

set URL = ''
if ( $#argv > 0 ) then
    set URL = "https://$1@github.com/earthcomputing/bjackson-triangle-demo.git"
endif

set body = "cd /home/demouser/earthcomputing/triangle-demo && git pull ${URL} && make -f Makefile.linux"

echo "$body"

foreach one ( ${alice} ${bob} ${carol} )
    ssh -t demouser@${one} "${body}"
end

