#include <stdio.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <pthread.h>
#include <time.h>

#include "cJSON.h"
#include "entl_user_api.h"

char *machine_name = NULL;

#define MAX_JSON_TEXT 512

// #define MAX_AIT_MESSAGE_SIZE 256

typedef struct link_device {
    char *name;
    int linkState;
    int entlState;
    int entlCount;
    char AITMessageR[MAX_AIT_MESSAGE_SIZE];
    char AITMessageS[MAX_AIT_MESSAGE_SIZE];
    char json[MAX_AIT_MESSAGE_SIZE];
} link_device_t;

char *entlStateString[] = { "IDLE", "HELLO", "WAIT", "SEND", "RECEIVE", "AM", "BM", "AH", "BH", "ERROR" };

static char *str4code(int code) {
    return (code < 9) ? entlStateString[code] : "UNKNOWN";
}

static pthread_mutex_t access_mutex;
#define ACCESS_LOCK pthread_mutex_lock(&access_mutex)
#define ACCESS_UNLOCK pthread_mutex_unlock(&access_mutex)

#define LOCALHOST "127.0.0.1"
#define DEFAULT_DBG_PORT  1337

static int w_socket;

// stream JSON text data to server
static void toServer(char *json) {
    write(w_socket, json, strlen(json));
    // printf("toServer: %s", json);
}

static int sock;
/*
    ioctl(sock, SIOCDEVPRIVATE_ENTL_RD_CURRENT, req)
    ioctl(sock, SIOCDEVPRIVATE_ENTL_RD_ERROR, req)
    ioctl(sock, SIOCDEVPRIVATE_ENTL_SET_SIGRCVR, req)
    ioctl(sock, SIOCDEVPRIVATE_ENTT_READ_AIT, req)
    ioctl(sock, SIOCDEVPRIVATE_ENTT_SEND_AIT, req)
*/

#define JSON_PAT "{" \
    "\"machineName\":\"%s\"," \
    "\"deviceName\":\"%s\"," \
    "\"linkState\":\"%s\"," \
    "\"entlState\":\"%s\"," \
    "\"entlCount\":\"%d\"," \
    "\"AITSent\":\"%s\"," \
    "\"AITRecieved\": \"%s\"" \
"}\n"

// translate device state to JSON text
static int toJSON(link_device_t *dev) {
    if (NULL == dev) return 0;

    int size = snprintf(dev->json, MAX_AIT_MESSAGE_SIZE, JSON_PAT,
        machine_name,
        dev->name,
        (dev->linkState) ? "UP" : "DOWN",
        str4code(dev->entlState),
        dev->entlCount,
        dev->AITMessageS,
        dev->AITMessageR
    );
    if (size < 0) { perror("JSON snprintf"); }
    return size;
}

static void init_link(link_device_t *l, char *port_id) {
    memset(l, 0, sizeof(link_device_t));
    l->name = port_id;
    l->entlState = 100; // unknown
    snprintf(l->AITMessageS, MAX_AIT_MESSAGE_SIZE, " ");
    snprintf(l->AITMessageR, MAX_AIT_MESSAGE_SIZE, " ");
}

static int entt_read_ait(struct ifreq *req, struct entt_ioctl_ait_data *atomic_msg) {
    memset(atomic_msg, 0, sizeof(struct entt_ioctl_ait_data));
    req->ifr_data = (char *)atomic_msg;

    ACCESS_LOCK;
    int rc = ioctl(sock, SIOCDEVPRIVATE_ENTT_READ_AIT, req);
    if (rc == -1) {
        perror("SIOCDEVPRIVATE_ENTT_READ_AIT");
    }
    else {
        char buf[MAX_AIT_MESSAGE_SIZE];
        memcpy(buf, atomic_msg->data, atomic_msg->message_len);
        printf("entt_read_ait - interface: %s num_messages: %d, \"%s\"\n", req->ifr_name, atomic_msg->num_messages, buf);
    }
    ACCESS_UNLOCK;
    return rc;
}

static int entt_send_ait(struct ifreq *req, struct entt_ioctl_ait_data *atomic_msg, char *msg) {
    atomic_msg->message_len = strlen(msg) + 1;
    snprintf(atomic_msg->data, MAX_AIT_MESSAGE_SIZE, "%s", msg);
    req->ifr_data = (char *)atomic_msg;

    ACCESS_LOCK;
    int rc = ioctl(sock, SIOCDEVPRIVATE_ENTT_SEND_AIT, req);
    if (rc == -1) {
        perror("SIOCDEVPRIVATE_ENTT_SEND_AIT");
    }
    else {
        printf("entt_send_ait - interface: %s msg: \"%s\" \n", req->ifr_name, msg);
    }
    ACCESS_UNLOCK;
    return rc;
}

static int entl_set_sigrcvr(struct ifreq *req, struct entl_ioctl_data *cdata, char *port_id, int pid) {
    memset(req, 0, sizeof(struct ifreq));
    strncpy(req->ifr_name, port_id, sizeof(req->ifr_name));
    memset(cdata, 0, sizeof(struct entl_ioctl_data));
    cdata->pid = pid;
    req->ifr_data = (char *)cdata;

    ACCESS_LOCK;
    int rc = ioctl(sock, SIOCDEVPRIVATE_ENTL_SET_SIGRCVR, req);
    if (rc == -1) {
        perror("SIOCDEVPRIVATE_ENTL_SET_SIGRCVR");
    }
    else {
        printf("entl_set_sigrcvr - interface: %s\n", req->ifr_name);
    }
    ACCESS_UNLOCK;
    return rc;
}

static int entl_rd_error(struct ifreq *req, struct entl_ioctl_data *cdata) {
    memset(cdata, 0, sizeof(struct entl_ioctl_data));
    req->ifr_data = (char *)cdata;

    ACCESS_LOCK;
    int rc = ioctl(sock, SIOCDEVPRIVATE_ENTL_RD_ERROR, req);
    if (rc == -1) {
        perror("SIOCDEVPRIVATE_ENTL_RD_ERROR");
    }
    else {
        printf("entl_rd_error - interface: %s\n", req->ifr_name);
    }
    ACCESS_UNLOCK;
    return rc;
}

static int entl_rd_current(struct ifreq *req, struct entl_ioctl_data *cdata) {
    memset(cdata, 0, sizeof(struct entl_ioctl_data));
    req->ifr_data = (char *)cdata;

    ACCESS_LOCK;
    int rc = ioctl(sock, SIOCDEVPRIVATE_ENTL_RD_CURRENT, req);
    if (rc == -1) {
        perror("SIOCDEVPRIVATE_ENTL_RD_CURRENT");
    }
    else {
        // called periodically
        // printf("entl_rd_current - interface: %s state: %d (%s)\n", req->ifr_name, cdata->state.current_state, str4code(cdata->state.current_state));
    }
    ACCESS_UNLOCK;
    return rc;
}

#define NUM_INTERFACES 4

static char *port_name[NUM_INTERFACES] = { "enp6s0", "enp7s0", "enp8s0", "enp9s0" };

static struct entl_ioctl_data entl_data[NUM_INTERFACES];
static struct ifreq ifr[NUM_INTERFACES];
struct entt_ioctl_ait_data ait_data[NUM_INTERFACES];
link_device_t links[NUM_INTERFACES];

// get hardware state, post to server (ENTT_READ_AIT)
static void entl_ait_sig_handler(int signum) {
    printf("***  entl_ait_sig_handler signal: (%d) ***\n", signum);

    if (signum != SIGUSR2) { return; }

    for (int i = 0; i < NUM_INTERFACES; i++) {
        struct ifreq *req = &ifr[i];
        struct entt_ioctl_ait_data *atomic_msg = &ait_data[i];
        link_device_t *l = &links[i];

        int rc = entt_read_ait(req, atomic_msg);
        if (rc == -1) continue;

        if (atomic_msg->message_len == 0) {
            printf("entl_ait_sig_handler - interface: %s message_len: 0\n ", req->ifr_name);
            continue;
        }

        memcpy(l->AITMessageR, atomic_msg->data, atomic_msg->message_len);
        toJSON(l);
        toServer(l->json);
    }
}

// get hardware state, post to server (ENTL_RD_ERROR)
void entl_error_sig_handler(int signum) {
    printf("***  entl_error_sig_handler signal: (%d) ***\n", signum);

    if (signum != SIGUSR1) { return; }

    for (int i = 0; i < NUM_INTERFACES; i++) {
        struct ifreq *req = &ifr[i];
        struct entl_ioctl_data *cdata = &entl_data[i];
        link_device_t *l = &links[i];

        int rc = entl_rd_error(req, cdata);
        if (rc != -1) {
            l->entlState = cdata->state.current_state;
            l->entlCount = cdata->state.event_i_know;
            l->linkState = cdata->link_state;
            toJSON(l);
            toServer(l->json);
        }
    }
}

#define INMAX 9000
static char inlin[INMAX+1];

// read available data from socket
static int read_window() {
    int n = INMAX;
    int rr = read(w_socket, inlin, n);
    if (rr <= 0) { rr = 0; }
    inlin[rr] = '\0';
    return rr;
}

static pthread_t read_thread;

// worker thread : read from socket, entt_send_ait(port, msg)
static void *read_task(void *me) {
    printf( "read_task started\n");

    while (1) {
        if (!read_window()) { sleep(1); continue; }
        if (inlin[0] == '\n') { continue; }

        cJSON *root = cJSON_Parse(inlin);
        if (!root) { continue; }

        char *port = cJSON_GetObjectItem(root, "port")->valuestring;
        char *message = cJSON_GetObjectItem(root, "message")->valuestring;

        // FIXME : message length
        size_t len = strlen(message);
        size_t few = (len < (MAX_AIT_MESSAGE_SIZE - 1)) ? len : (MAX_AIT_MESSAGE_SIZE - 1);
        char some[MAX_AIT_MESSAGE_SIZE];
        strncpy(some, message, few);
        some[few + 1] = 0;

        for (int i = 0; i < NUM_INTERFACES; i++) {
            struct ifreq *req = &ifr[i];
            struct entt_ioctl_ait_data *atomic_msg = &ait_data[i];
            char *port_id = port_name[i];

            if (!strcmp(port, port_id)) {
                // printf("read_task - port: %s index: %d message: \"%s\"\n", port, i, message);
                entt_send_ait(req, atomic_msg, message);
                break;
            }
        }
        cJSON_Delete(root);
    }
}

static int open_socket() {
    char *addr = LOCALHOST;
    int sin_port = DEFAULT_DBG_PORT;
    struct sockaddr_in sockaddr;

    sockaddr.sin_family = AF_INET;
    sockaddr.sin_addr.s_addr = inet_addr(addr);
    sockaddr.sin_port = htons(sin_port);

    int sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0) { perror("Can't create socket\n"); return sockfd; }

    printf("connect port: %d\n", sin_port);
    int st = connect(sockfd, (struct sockaddr *) &sockaddr, sizeof(struct sockaddr));
    if (st < 0) {
        perror("Can't bind socket");
        close(sockfd);
        return st;
    }

    return sockfd;
}

// opens output socket DEFAULT_DBG_PORT(127.0.0.1:1337) and continually streams data to it
int main (int argc, char **argv) {
    if (argc != 2) {
        printf("Usage %s <machine_name> (e.g. %s foobar)\n", argv[0], argv[0]);
        return -1;
    }

    printf("Server Address: Machine Name: %s\n", argv[1]);
    machine_name = argv[1];

    int sockfd = open_socket();
    if (sockfd < 0) { return -1; }

    pthread_mutex_init(&access_mutex, NULL);

    w_socket = sockfd;

    // send initial state to server
    for (int i = 0; i < NUM_INTERFACES; i++) {
        link_device_t *l = &links[i];
        char *port_id = port_name[i];
        init_link(l, port_id);
        toJSON(l);
        toServer(l->json);
    }

    sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) { perror("cannot create socket"); return 0; }

    signal(SIGUSR1, entl_error_sig_handler);
    signal(SIGUSR2, entl_ait_sig_handler);

    pid_t pid = getpid();
    printf("pid : %d\n", pid);

    for (int i = 0; i < NUM_INTERFACES; i++) {
        struct ifreq *req = &ifr[i];
        struct entl_ioctl_data *cdata = &entl_data[i];
        char *port_id = port_name[i];
        entl_set_sigrcvr(req, cdata, port_id, pid);
    }

    for (int i = 0; i < NUM_INTERFACES; i++) {
        struct ifreq *req = &ifr[i];
        struct entl_ioctl_data *cdata = &entl_data[i];
        entl_rd_error(req, cdata);
    }

    int rc = pthread_create(&read_thread, NULL, read_task, NULL);
    if (rc != 0) printf("pthread_create failed\n");

    // loop : ENTL_RD_CURRENT, toServer
    printf("Entering app loop \n");
    while (1) {
        for (int i = 0; i < NUM_INTERFACES; i++) {
            struct ifreq *req = &ifr[i];
            struct entl_ioctl_data *cdata = &entl_data[i];
            link_device_t *l = &links[i];

            int rc = entl_rd_current(req, cdata);
            if (rc == -1) continue;

            // link_state, current_state, event_i_know
            if ((l->entlState != cdata->state.current_state)
            ||  (l->entlCount != cdata->state.event_i_know)
            ||  (l->linkState != cdata->link_state)) {
                l->entlState = cdata->state.current_state;
                l->entlCount = cdata->state.event_i_know;
                l->linkState = cdata->link_state;
                toJSON(l);
                toServer(l->json);
            }
        }
        sleep(1);
    }

    // NOTREACHED
    return 0;
}
