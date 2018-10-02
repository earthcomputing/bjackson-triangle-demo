
derived from: https://github.com/earthcomputing/NALDD.git

short term :

    The 'adapter' depends upon device driver header files and cJSON.  I'd rather not include those things in this git repo, at least for now.

    CPPFLAGS += -I $(NALDD)/cJSON
    CPPFLAGS += -I $(NALDD)/entl_drivers/e1000e-3.3.4/src


/Users/bjackson/earth-computing/git-projects/NALDD-github/entl_test

    README.txt - renamed to README-Ubuntu
    demo_cell.html
    demo_client.c - renamed to adapter.c
    demo_server_c.js
    do_demo
    cJSON.c

Node.js build:

    npm install body-parser express socket.io

New files:

    README.md
    activate-demo.sh - remote display setup script
    Makefile - build adapter (generic)
    Makefile.linux - build adapter (linux)
    images - background images (Alice, Bob, Carol)
    package.json - build demo_server_c.js
    post-frame.pl - test script for POST API

