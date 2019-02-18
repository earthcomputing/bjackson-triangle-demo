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
#include <syslog.h>

#include "cJSON.h"
#include "entl_user_api.h"

char *machine_name = NULL;

// 2 * string[256] + 4 "short" strings plus 1 number plus syntax overhead
#define MAX_JSON_TEXT 1024

// #define MAX_AIT_MESSAGE_SIZE 256

typedef struct link_device {
    char *name;
    int linkState; // entl_error_sig_handler
    int entlState; // entl_error_sig_handler
    int entlCount; // entl_error_sig_handler
    char AITMessageR[MAX_AIT_MESSAGE_SIZE]; // entl_ait_sig_handler
    char AITMessageS[MAX_AIT_MESSAGE_SIZE]; // unused ??
    long recvTime;
    char json[MAX_JSON_TEXT]; // toJSON
} link_device_t;

char *entlStateString[] = { "IDLE", "HELLO", "WAIT", "SEND", "RECEIVE", "AM", "BM", "AH", "BH", "ERROR" };

static long now() {
    struct timeval t;
    int rc  = gettimeofday(&t, NULL);
    long epoch = (t.tv_sec * 1000 * 1000) + t.tv_usec;
    return epoch;
}

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
    // syslog(LOG_DEBUG, "(%s) toServer: %s", machine_name, json);
}

static int sock;
/*
    ioctl(sock, SIOCDEVPRIVATE_ENTL_RD_CURRENT, req)
    ioctl(sock, SIOCDEVPRIVATE_ENTL_RD_ERROR, req)
    ioctl(sock, SIOCDEVPRIVATE_ENTL_SET_SIGRCVR, req)
    ioctl(sock, SIOCDEVPRIVATE_ENTT_READ_AIT, req)
    ioctl(sock, SIOCDEVPRIVATE_ENTT_SEND_AIT, req)
*/

// FIXME : can't contain NUL (\0000)

/* Render the cstring provided to an escaped version that can be printed. */
static char *json_escape_string(char *str, char *out, int maxlen) {

    /* empty string */
    if (!str) {
        if (maxlen < 1) { return 0; }
        return strcpy(out, "");
    }

    /* set "flag" to 1 if something needs to be escaped */
    int flag = 0;
    char *ptr; for (ptr = str; *ptr; ptr++) {
        char octet = *ptr;
        flag |= (
            ((octet > 0) && (octet < 32)) /* unprintable characters */
          || (octet == '\"') /* double quote */
          || (octet == '\\') /* backslash */
        ) ? 1 : 0;
    }

    /* no characters have to be escaped */
    if (!flag) {
        int len = ptr - str;
        if (maxlen < len + 1) { return 0; }
        return strcpy(out, str);
    }

    /* calculate additional space that is needed for escaping */
    int len = 0;
    unsigned char token;
    for (char *ptr = str; (token = *ptr); ptr++) {
        if (strchr("\"\\\b\f\n\r\t", token)) {
            len += 2; /* +1 for the backslash */
        }
        else if (token < 32) {
            len += 6; /* \uXXXX */
        }
        else {
            len++;
        }
    }

    if (maxlen < len + 1) { return 0; }

    /* copy the string */
    char *ptr2 = out;
    for (char *ptr = str; *ptr; ptr++) {
        char octet = *ptr;
        if (((unsigned char)octet > 31) && (octet != '\"') && (octet != '\\')) {
            /* normal character, copy */
            *ptr2++ = octet;
        }
        else {
            /* character needs to be escaped */
            *ptr2++ = '\\';
            unsigned char token;
            switch (token = octet) {
                case '\\': *ptr2++ = '\\'; break;
                case '\"': *ptr2++ = '\"'; break;
                case '\b': *ptr2++ = 'b'; break;
                case '\f': *ptr2++ = 'f'; break;
                case '\n': *ptr2++ = 'n'; break;
                case '\r': *ptr2++ = 'r'; break;
                case '\t': *ptr2++ = 't'; break;
                default:
                    /* escape and print as unicode codepoint */
                    sprintf(ptr2, "u%04x", token);
                    ptr2 += 5;
                    break;
            }
        }
    }
    *ptr2++ = '\0';
    return out;
}

// line-oriened ASCII data record(s)
// FIXME : AITRecieved MAY NOT contain newlines! or JSON formatting, or bare double-quotes ...
#define JSON_PAT "{" \
    "\"machineName\":\"%s\"," \
    "\"deviceName\":\"%s\"," \
    "\"linkState\":\"%s\"," \
    "\"entlState\":\"%s\"," \
    "\"entlCount\":\"%d\"," \
    "\"AITSent\":\"%s\"," \
    "\"AITRecieved\":\"%s\"," \
    "\"recvTime\":\"%ld\"" \
"}\n"

// translate device state to JSON text
// the length of the strings produced is locale-dependent and difficult to predict
// LANG=C LC_ALL=C
static int toJSON(link_device_t *dev) {
    if (NULL == dev) return 0;
    char encoded_recv[2*MAX_AIT_MESSAGE_SIZE];

    char *p = json_escape_string(dev->AITMessageR, encoded_recv, 2*MAX_AIT_MESSAGE_SIZE);
    if (!p) { syslog(LOG_WARNING, "(%s) toJSON - AIT read msg size exceeded", machine_name); return -1; }

    int size = snprintf(dev->json, MAX_JSON_TEXT, JSON_PAT,
        machine_name,
        dev->name,
        (dev->linkState) ? "UP" : "DOWN",
        str4code(dev->entlState),
        dev->entlCount,
        dev->AITMessageS,
        encoded_recv,
        dev->recvTime
    );
    if (size < 0) { syslog(LOG_WARNING, "(%s) JSON snprintf: %m", machine_name); }
    return size;
}

static void init_link(link_device_t *l, char *port_id) {
    memset(l, 0, sizeof(link_device_t));
    l->name = port_id;
    l->entlState = 100; // unknown
    snprintf(l->AITMessageS, MAX_AIT_MESSAGE_SIZE, " ");
    snprintf(l->AITMessageR, MAX_AIT_MESSAGE_SIZE, " ");
    l->recvTime = now();
}

static int entt_read_ait(struct ifreq *req, struct entt_ioctl_ait_data *atomic_msg) {
    memset(atomic_msg, 0, sizeof(struct entt_ioctl_ait_data));
    req->ifr_data = (char *)atomic_msg;

    ACCESS_LOCK;
    int rc = ioctl(sock, SIOCDEVPRIVATE_ENTT_READ_AIT, req);
    if (rc == -1) {
        syslog(LOG_WARNING, "(%s) SIOCDEVPRIVATE_ENTT_READ_AIT: %m", machine_name);
    }
    else if (atomic_msg->message_len > 0) {
        if (atomic_msg->message_len >= MAX_AIT_MESSAGE_SIZE) {
            syslog(LOG_WARNING, "(%s) SIOCDEVPRIVATE_ENTT_READ_AIT: oversize msg: %d", machine_name, atomic_msg->message_len);
        }
        // FIXME: string/binary ambiguity
        char buf[MAX_AIT_MESSAGE_SIZE];
        memset(buf, 0, MAX_AIT_MESSAGE_SIZE);
        memcpy(buf, atomic_msg->data, atomic_msg->message_len);
        syslog(LOG_INFO, "(%s) entt_read_ait - interface: %s num_messages: %d, num_queued: %d, \"%s\"\n", machine_name, req->ifr_name, atomic_msg->num_messages, atomic_msg->num_queued, buf);
    }
    else if ((atomic_msg->num_messages != 0) && (atomic_msg->num_queued != 0)) {
        syslog(LOG_INFO, "(%s) entt_read_ait - interface: %s num_messages: %d, num_queued: %d\n", machine_name, req->ifr_name, atomic_msg->num_messages, atomic_msg->num_queued);
    }
    ACCESS_UNLOCK;
    return rc;
}

static int entt_send_ait(struct ifreq *req, struct entt_ioctl_ait_data *atomic_msg) {
    req->ifr_data = (char *)atomic_msg;

    ACCESS_LOCK;
    int rc = ioctl(sock, SIOCDEVPRIVATE_ENTT_SEND_AIT, req);
    if (rc == -1) {
        syslog(LOG_WARNING, "(%s) SIOCDEVPRIVATE_ENTT_SEND_AIT: %m", machine_name);
    }
    else {
        syslog(LOG_INFO, "(%s) entt_send_ait - interface: %s msg: \"%s\"\n", machine_name, req->ifr_name, atomic_msg->data);
    }
    ACCESS_UNLOCK;
    return rc;
}

static int entl_set_sigrcvr(struct ifreq *req, struct entl_ioctl_data *cdata, char *port_id, int pid) {
    memset(cdata, 0, sizeof(struct entl_ioctl_data));
    cdata->pid = pid;

    memset(req, 0, sizeof(struct ifreq));
    strncpy(req->ifr_name, port_id, sizeof(req->ifr_name));
    req->ifr_data = (char *)cdata;

    ACCESS_LOCK;
    int rc = ioctl(sock, SIOCDEVPRIVATE_ENTL_SET_SIGRCVR, req);
    if (rc == -1) {
        syslog(LOG_WARNING, "(%s) SIOCDEVPRIVATE_ENTL_SET_SIGRCVR: %m", machine_name);
    }
    else {
        syslog(LOG_NOTICE, "(%s) entl_set_sigrcvr - interface: %s pid: %d\n", machine_name, req->ifr_name, pid);
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
        syslog(LOG_WARNING, "(%s) SIOCDEVPRIVATE_ENTL_RD_ERROR: %m", machine_name);
    }
    else {
        // syslog(LOG_NOTICE, "(%s) entl_rd_error - interface: %s\n", machine_name, req->ifr_name);
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
        syslog(LOG_WARNING, "(%s) SIOCDEVPRIVATE_ENTL_RD_CURRENT: %m", machine_name);
    }
    else {
        // called periodically
        // syslog(LOG_INFO, "(%s) entl_rd_current - interface: %s state: %d (%s)\n", machine_name, req->ifr_name, cdata->state.current_state, str4code(cdata->state.current_state));
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
    syslog(LOG_NOTICE, "(%s) *** entl_ait_sig_handler signal: (%d) ***\n", machine_name, signum);

    if (signum != SIGUSR2) { return; }

    for (int i = 0; i < NUM_INTERFACES; i++) {
        struct ifreq *req = &ifr[i];
        struct entt_ioctl_ait_data *atomic_msg = &ait_data[i];
        link_device_t *l = &links[i];

        int rc = entt_read_ait(req, atomic_msg);
        if (rc == -1) continue;
        if (atomic_msg->message_len == 0) continue;

        syslog(LOG_INFO, "(%s) entl_ait_sig_handler - interface: %s message_len: %d\n", machine_name, req->ifr_name, atomic_msg->message_len);

        // FIXME: string/binary ambiguity
        // what if atomic_msg->data is missing NUL ??
        l->recvTime = now();
        memcpy(l->AITMessageR, atomic_msg->data, atomic_msg->message_len);
        toJSON(l);
        toServer(l->json);
        syslog(LOG_INFO, "(%s) link state: %s", machine_name, l->json);
    }
}

// get hardware state, post to server (ENTL_RD_ERROR)
void entl_error_sig_handler(int signum) {
    syslog(LOG_NOTICE, "(%s) ***  entl_error_sig_handler signal: (%d) ***\n", machine_name, signum);

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
            syslog(LOG_INFO, "(%s) link state: %s", machine_name, l->json);
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
    syslog(LOG_INFO, "(%s) read_task started\n", machine_name);

    while (1) {
        if (!read_window()) { sleep(1); continue; }
        if (inlin[0] == '\n') { continue; }

        cJSON *root = cJSON_Parse(inlin);
        if (!root) { continue; }

        char *port = cJSON_GetObjectItem(root, "port")->valuestring;
        char *message = cJSON_GetObjectItem(root, "message")->valuestring;
        // FIXME: string !!

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
                // syslog(LOG_INFO, "(%s) read_task - port: %s index: %d message: \"%s\"\n", machine_name, port, i, message);
                atomic_msg->message_len = strlen(message) + 1;
                int size = snprintf(atomic_msg->data, MAX_AIT_MESSAGE_SIZE, "%s", message);
                if (size < 0) { syslog(LOG_WARNING, "(%s) read_task - msg size exceeded: %m", machine_name); }
                entt_send_ait(req, atomic_msg);
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

    syslog(LOG_INFO, "(%s) connect port: %d\n", machine_name, sin_port);
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

    const char *ident = NULL; // argv[0]
    int option = LOG_ODELAY|LOG_PID;
    int facility = LOG_USER;
    openlog(ident, option, facility);

    syslog(LOG_INFO, "Server Address: Machine Name: %s\n", argv[1]);
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
    if (sock < 0) { perror("cannot create socket"); return -1; }

    signal(SIGUSR1, entl_error_sig_handler);
    signal(SIGUSR2, entl_ait_sig_handler);

    pid_t pid = getpid();
    syslog(LOG_INFO, "(%s) pid : %d\n", machine_name, pid);

    syslog(LOG_INFO, "(%s) registering signal handlers\n", machine_name);
    for (int i = 0; i < NUM_INTERFACES; i++) {
        struct ifreq *req = &ifr[i];
        struct entl_ioctl_data *cdata = &entl_data[i];
        char *port_id = port_name[i];
        int rc = entl_set_sigrcvr(req, cdata, port_id, pid);
        // FIXME: printf should be here rather than within entl_set_sigrcvr
    }

    for (int i = 0; i < NUM_INTERFACES; i++) {
        struct ifreq *req = &ifr[i];
        struct entl_ioctl_data *cdata = &entl_data[i];
        int rc = entl_rd_error(req, cdata);
        // FIXME: printf should be here rather than within entl_rd_error
    }

    int rc = pthread_create(&read_thread, NULL, read_task, NULL);
    if (rc != 0) syslog(LOG_INFO, "(%s) pthread_create failed\n", machine_name);

    // loop : ENTL_RD_CURRENT, toServer
    syslog(LOG_INFO, "(%s) update loop\n", machine_name);
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
    closelog();
    return 0;
}
