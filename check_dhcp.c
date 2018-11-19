/*
 * Copyright (c) 2016 Jan-Philipp Litza <janphilipp@litza.de>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

/*
    This is a self-written DHCP check specifically for the purpose of
    monitoring a DHCP server in a batman-adv mesh:
    * It sends a DHCPDISCOVER via layer 2 unicast to the server it is given
      as layer 3 address. This bypasses the gateway mechanism of batman-adv.
    * It does *not* pretend to be a relay agent, thus receiving an answer on
      port 68 (unfiltered by gluon-ebtables-filter-ra-dhcp) instead of
      port 67 (as the check_dhcp from monitoring-plugins-basic does, which
      is filtered by gluon-ebtables-filter-ra-dhcp)
*/

#include <alloca.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <linux/if_packet.h>
#include <net/ethernet.h>
#include <net/if.h>
#include <net/if_arp.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/udp.h>
#include <sys/ioctl.h>
#include <sys/socket.h>

#include <libgen.h>

#define DHCP_SERVER_PORT htons(67)
#define DHCP_CLIENT_PORT htons(68)
#define DHCP_MAGIC htonl(0x63825363)
#define DHCP_MAX_MSG_SIZE 576

#define DHCP_OPTION_TYPE_PAD     0x00
#define DHCP_OPTION_TYPE_MSGTYPE 0x35
#define DHCP_OPTION_TYPE_SERVER  0x36
#define DHCP_OPTION_TYPE_END     0xff

#define DHCPDISCOVER 0x01
#define DHCPOFFER    0x02

#define BOOTREQUEST 1
#define BOOTREPLY   2

#define HWADDR_SIZE 6
#define BUFSIZE 1024

#ifdef DEBUG
#define ASSERT(stmt) \
    if(!(stmt)) { \
        fprintf(stderr, "Packet failed validation: " #stmt "\n"); \
        continue; \
    }
#else
#define ASSERT(stmt) if(!(stmt)) continue;
#endif

struct dhcp_option {
    uint8_t type;
    uint8_t len;
    uint8_t data[];
};

struct dhcp_packet {
    uint8_t op;
    uint8_t htype;
    uint8_t hlen;
    uint8_t hops;
    uint32_t xid;
    uint16_t secs;
    uint16_t flags;
    uint32_t ciaddr;
    uint32_t yiaddr;
    uint32_t siaddr;
    uint32_t giaddr;
    uint8_t chaddr[16];
    char sname[64];
    char file[128];
    uint32_t magic;
    struct dhcp_option options[];
};

int make_iface_ioctl(struct ifreq *ifr, const char *ifname, int ioctl_n) {
    int fd;
    strncpy(ifr->ifr_name, ifname, sizeof(ifr->ifr_name));
    ifr->ifr_name[sizeof(ifr->ifr_name)-1] = '\0';

    fd = socket(AF_UNIX, SOCK_DGRAM, 0);
    if (fd < 0) {
        perror("socket");
        return -1;
    }
    if (ioctl(fd, ioctl_n, ifr) == -1) {
        perror("ioctl");
        close(fd);
        return -1;
    }
    close(fd);
    return 0;
}

int get_hwaddr_of_iface(const char *ifname, void *hwaddr) {
    struct ifreq ifr;

    if (make_iface_ioctl(&ifr, ifname, SIOCGIFHWADDR) < 0)
        return -1;

    if (ifr.ifr_hwaddr.sa_family != ARPHRD_ETHER) {
        fprintf(stderr, "Not an ethernet interface: %s\n", ifname);
        return -1;
    }

    memcpy(hwaddr, ifr.ifr_hwaddr.sa_data, HWADDR_SIZE);
    return 0;
}

int get_ifindex(char *ifname) {
    struct ifreq ifr;
    if (make_iface_ioctl(&ifr, ifname, SIOCGIFINDEX) < 0)
        return -1;
    return ifr.ifr_ifindex;
}

void sighandler(int signal) {
    exit(1);
}

void usage(char *progname) {
    fprintf(stderr, "Usage: %s [-t <timeout>] <iface> <server>\n", basename(progname));
}

int main(int argc, char *argv[]) {
    int ifidx;
    uint8_t hwaddr[HWADDR_SIZE];
    uint32_t xid;
    struct in_addr server;
    size_t received;
    int opt, timeout = 10;
    int outsock, insock;
    char *ifname;
    void *buf;
    struct dhcp_packet *dhcp;
    struct iphdr *ip;
    struct udphdr *udp;
    struct sockaddr_in sin = {};
    struct sockaddr_ll sll = {};
    struct sigaction sa = {};

    if (argc < 3) {
    }

    while ((opt = getopt(argc, argv, "ht:")) != -1) {
        switch(opt) {
            case 't':
                timeout = atoi(optarg);
                break;
            case 'h':
                usage(argv[0]);
                exit(0);
            default:
                usage(argv[0]);
                return -1;
        }
    }

    if (optind > argc - 2) {
        usage(argv[0]);
        return -1;
    }
    ifname = argv[optind];

    // validate input
    ifidx = get_ifindex(ifname);
    if (ifidx < 0) {
        fprintf(stderr, "Invalid interface: %s\n", ifname);
        return -1;
    }
    if (get_hwaddr_of_iface(ifname, &hwaddr) < 0) {
        fprintf(stderr, "Failed to get MAC address of interface %s.\n", ifname);
        return -1;
    }
    if (inet_pton(AF_INET, argv[optind+1], &server.s_addr) != 1) {
        fprintf(stderr, "Invalid server address: %s\n", argv[optind+1]);
        return -1;
    }

    buf = alloca(BUFSIZE);
    memset(buf, '\0', BUFSIZE);

    // generate XID
    srand(time(0));
    xid = rand();

    // generate discover packet
    dhcp = buf;
    dhcp->op = BOOTREQUEST;
    dhcp->htype = ARPHRD_ETHER;
    dhcp->hlen = HWADDR_SIZE;
    dhcp->xid = xid;
    memcpy(dhcp->chaddr, &hwaddr, HWADDR_SIZE);
    dhcp->magic = DHCP_MAGIC;
    dhcp->options[0].type = DHCP_OPTION_TYPE_MSGTYPE;
    dhcp->options[0].len = 1;
    dhcp->options[0].data[0] = DHCPDISCOVER;
    // we actually set options[1]->type here, but thanks to the data in
    // options[0] this would be misaligned
    dhcp->options[0].data[1] = DHCP_OPTION_TYPE_END;

    // open sockets
    outsock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (outsock < 0) {
        perror("socket(outsock)");
        return -2;
    }
    sin.sin_family = AF_INET;
    sin.sin_port = DHCP_CLIENT_PORT;
    sin.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(outsock, (struct sockaddr *)&sin, sizeof(struct sockaddr_in)) < 0) {
        perror("bind(outsock)");
        fprintf(stderr, "Probably we are missing CAP_NET_BIND_SERVICE\n");
        return -2;
    }

    insock = socket(PF_PACKET, SOCK_DGRAM, htons(ETH_P_ALL));
    if (insock < 0) {
        perror("socket(insock)");
        fprintf(stderr, "Probably we are missing CAP_NET_RAW\n");
        return -2;
    }
    sll.sll_family = AF_PACKET;
    sll.sll_protocol = htons(ETH_P_IP);
    sll.sll_ifindex = ifidx;
    if (bind(insock, (struct sockaddr *)&sll, sizeof(struct sockaddr_ll)) < 0) {
        perror("bind(insock)");
        return -2;
    }

    // send DHCPDISCOVER
    sin.sin_port = htons(67);
    sin.sin_addr = server;
    sendto(outsock, dhcp, sizeof(struct dhcp_packet) + 4, 0, (struct sockaddr *)&sin, sizeof(struct sockaddr_in));
    // we do not yet close the socket so we do not generate an ICMP response to
    // the answer of the DHCP server if he confirms our address

    // set timeout
    sa.sa_handler = sighandler;
    sigaction(SIGALRM, &sa, NULL);
    alarm(timeout);

    // listen for response
    ip = buf;
    while(1) {
        received = recv(insock, ip, BUFSIZE, 0);
        ASSERT(received >= sizeof(struct iphdr));
        ASSERT(ip->version == IPVERSION);
        ASSERT(ip->protocol == IPPROTO_UDP);
        ASSERT(ip->saddr == server.s_addr);
        ASSERT(received >= 4*ip->ihl + sizeof(struct udphdr));

        udp = (struct udphdr *)((void*)ip + 4*ip->ihl);
        ASSERT(udp->uh_sport == DHCP_SERVER_PORT);
        ASSERT(udp->uh_dport == DHCP_CLIENT_PORT);
        ASSERT(ntohs(ip->tot_len) == ntohs(udp->uh_ulen) + 4*ip->ihl);
        ASSERT(ntohs(udp->uh_ulen) >= sizeof(struct udphdr) + sizeof(struct dhcp_packet));
        ASSERT(ntohs(udp->uh_ulen) <= sizeof(struct udphdr) + DHCP_MAX_MSG_SIZE);
        ASSERT(received >= ntohs(ip->tot_len));

        dhcp = (struct dhcp_packet *)((void*)udp + 8);
        ASSERT(dhcp->op == BOOTREPLY);
        ASSERT(dhcp->htype == ARPHRD_ETHER);
        ASSERT(dhcp->hlen == HWADDR_SIZE);
        ASSERT(dhcp->xid == xid);
        ASSERT(dhcp->yiaddr != 0);
        ASSERT(!memcmp(dhcp->chaddr, &hwaddr, HWADDR_SIZE));
        ASSERT(dhcp->magic == DHCP_MAGIC);

        struct dhcp_option *option = dhcp->options;
        bool end_of_options = false, had_server = false, had_msgtype = false;
        while ((void*)option <= (void*)ip + ntohs(ip->tot_len) - sizeof(struct dhcp_option)) {
            if (option->type == DHCP_OPTION_TYPE_PAD) {
                option = (void*)option + 1;
                continue;
            }
            if (option->type == DHCP_OPTION_TYPE_END) {
                end_of_options = true;
                option = (void*)option + 1;
                continue;
            }
            ASSERT(!end_of_options);

            // short-circuit if option is truncated
            if((void*)option >= (void*)ip + ntohs(ip->tot_len) - sizeof(struct dhcp_option) - option->len)
                break;

            if (option->type == DHCP_OPTION_TYPE_MSGTYPE) {
                ASSERT(option->len == 1);
                ASSERT(option->data[0] == DHCPOFFER);
                had_msgtype = true;
            }

            if (option->type == DHCP_OPTION_TYPE_SERVER) {
                ASSERT(option->len == sizeof(struct in_addr));
                ASSERT(!memcmp(option->data, &server.s_addr, sizeof(struct in_addr)));
                had_server = true;
            }
            option = (void*)option + 2 + option->len;
        }
        ASSERT(had_msgtype);
        ASSERT(had_server);
        break;
    }
    alarm(0);

    return 0;
}
