# bjackson-triangle-demo
simplified and enhanced version of original hardware demo

## Earth Computing Cellular Fabric (ECCF) - Atomic Link demo

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

## Adapter build:

    make [-f Makefile.linux]

## Node.js build:

    sudo apt install nodejs
    sudo apt install npm
    npm install body-parser express socket.io

## CPAN update(s):

## various functions:

    http://localhost:3000/?machineName=Alice&color=yellow
    http://localhost:3000/config?trunc=-80
    http://localhost:3000/config?verbose=true
    http://localhost:3000/git-config
    http://localhost:3000/git-version
    http://localhost:3000/port/enp6s0
    http://localhost:3000/ports

## test notes:

    1. ./launch-eccf-server.sh [Alice Bob Carol]
    2. telnet localhost 1337
    3. .post-frame.pl -config=blueprint-sim.json /tmp/triangle-1536648431697765/frames.json

