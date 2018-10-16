
# INCLUDE = ../entl_drivers/e1000e-3.3.4/src/

NALDD = /home/demouser/earthcomputing/NALDD
NALDD = /Users/bjackson/earth-computing/git-projects/NALDD-github

CPPFLAGS += -I $(NALDD)/cJSON
CPPFLAGS += -I $(NALDD)/entl_drivers/e1000e-3.3.4/src

# LDLIBS += -lcjson
# cc -pthread -lpthread -I ${INCLUDE} -o $@ $?

SRCS = cJSON.c adapter.c
OBJS = $(SRCS: .c=.o)
TARGETS = adapter

adapter : $(OBJS)

all: ${TARGETS}

