# bjackson-triangle-demo
simplified and enhanced version of original hardware demo

## Earth Computing Cellular Fabric (ECCF) - Atomic Link demo

How to run the hardware-replay demo:

1. Identify a "packet trace" file:

    frames-square-1539761670617241.json.gz

2. Power on all 3 hosts ; check that network is up

3. Prepare the software components:

    piecemeal.sh frames-square-1539761670617241.json.gz

4. Check that the atomic links are 'active', up/down if necessary:
   [know the 'su' password??]

    wiggle.sh

5. Start the replay

    open poster.command (can do this thru finder)

## Origins

derived from: https://github.com/earthcomputing/NALDD.git

short term :

The 'adapter' depends upon device driver header files and cJSON.
I'd rather not include those things in this git repo, at least for now.

    CPPFLAGS += -I $(NALDD)/cJSON
    CPPFLAGS += -I $(NALDD)/entl_drivers/e1000e-3.3.4/src

## Copied from: NALDD/entl_test

    README.txt - renamed to README-Ubuntu
    demo_cell.html - renamed to cell-ui.html
    demo_client.c - renamed to adapter.c
    demo_server_c.js - renamed to eccf-server.js
    do_demo - renamed to launch-eccf-server.sh
    cJSON.c

## New files:

    README.md
    activate-demo.sh - remote display setup script
    Makefile - build adapter (generic)
    Makefile.linux - build adapter (linux)
    images - background images (Alice, Bob, Carol)
    package.json - build demo_server_c.js
    post-frame.pl - test script for POST API

## install notes:

    cd /home/demouser/earthcomputing
    git clone https://github.com/earthcomputing/bjackson-triangle-demo.git triangle-demo

## update notes:

    do-update.sh

    alice 172.16.1.67
    bob 172.16.1.40
    carol 172.16.1.105

    ssh demouser@172.16.1.67
    ssh demouser@172.16.1.40
    ssh demouser@172.16.1.105

    cd /home/demouser/earthcomputing/triangle-demo
    git pull
    make -f Makefile.linux


## Adapter build:

    make [-f Makefile.linux]

## Node.js build:

    sudo apt install nodejs
    sudo apt install npm
    npm install body-parser express socket.io

## CPAN update(s):

    cpan JSON
    cpan Data::GUID

## various functions:

    http://localhost:3000/?machineName=Alice&color=yellow
    http://localhost:3001/?machineName=Bob&color=cyan
    http://localhost:3002/?machineName=Carol&color=magenta

    http://localhost:3000/config?trunc=-80
    http://localhost:3000/config?verbose=true
    http://localhost:3000/git-config
    http://localhost:3000/git-version
    http://localhost:3000/port/enp6s0
    http://localhost:3000/ports

## test notes:

    validate.sh frames.json.gz

    1. ./launch-eccf-server.sh [Alice Bob Carol]
    2a. nodejs eccf-server.js Alice 3000 1337
    2b. nodejs eccf-server.js Bob   3001 1338
    2c. nodejs eccf-server.js Carol 3002 1339
    3a. telnet localhost 1337
    3b. telnet localhost 1338
    3c. telnet localhost 1339
    4. ./post-frame.pl -config=blueprint-sim.json /tmp/triangle-1536648431697765/frames.json
    5. ./post-frame.pl -config=blueprint-sim.json -delay=3 frames.json

## software update notes:

    adjust GITUSER
    host-update.command

## first time laptop setup:

    brew install telnet

    brew install nodejs
    which node
    which nodejs
    cd /usr/local/bin
    ln -s node nodejs
    npm install body-parser express socket.io

    brew install perl
    cpan JSON
    cpan Data::GUID

## ssh keys:

    create a key (.ssh : id_rsa, id_rsa.pub

    for each of the 3 hosts:
    add your public key (id_rsa.pub)  to:

        ~/.ssh/authorized_keys

