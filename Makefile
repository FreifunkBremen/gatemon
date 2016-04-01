
BINS=check_dhcp

all: $(BINS)
clean:
	rm -f $(BINS)

check_dhcp: check_dhcp.c
	gcc -o $@ $+

