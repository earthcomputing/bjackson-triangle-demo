ssh -t demouser@172.16.1.105 "cd /home/demouser/earthcomputing/triangle-demo ; git pull https://${GITUSER}@github.com/earthcomputing/bjackson-triangle-demo.git; make -f Makefile.linux ; exit 0"
ssh -t demouser@172.16.1.67 "cd /home/demouser/earthcomputing/triangle-demo ; git pull https://${GITUSER}@github.com/earthcomputing/bjackson-triangle-demo.git; make -f Makefile.linux ; exit 0"
ssh -t demouser@172.16.1.40 "cd /home/demouser/earthcomputing/triangle-demo ; git pull https://${GITUSER}@github.com/earthcomputing/bjackson-triangle-demo.git; make -f Makefile.linux ; exit 0"
