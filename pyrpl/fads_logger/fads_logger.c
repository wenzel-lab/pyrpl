#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <fcntl.h>
#include <ctype.h>
//#include <termios.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <stdint.h>


#define FATAL do { fprintf(stderr, "Error at line %d, file %s (%d) [%s]\n", \
  __LINE__, __FILE__, errno, strerror(errno)); exit(1); } while(0)

#define MAP_SIZE 4096UL
#define MAP_MASK (MAP_SIZE - 1)

// (void*)(-1) is the MAP_FAILED return value of mmap
void* map_base = (void*)(-1);

int main(int argc, char **argv) {
    int fd = -1;
    int ret_val = EXIT_SUCCESS;

//    unsigned long address_base = 0x40600110;
    unsigned long address_base = 0x40610000;
    unsigned long address_offset = 0x0;
    unsigned long address;
    unsigned long buffer_length = 0xf;
    unsigned long address_alignment = 0x4;

    if((fd = open("/dev/mem", O_RDONLY)) == -1) FATAL;
    map_base = mmap(0, MAP_SIZE, PROT_READ, MAP_SHARED, fd, address_base & ~MAP_MASK);
    if(map_base == (void *) -1) FATAL;

    while (1==1) {
        address_offset = (address_offset + address_alignment) % buffer_length;
        address = address_base + address_offset;
        void* virt_addr = map_base + (address & MAP_MASK);
        uint32_t read_result = 0;
        read_result = *((uint32_t *) virt_addr);
        printf("0x%08x : 0x%08x\n", address, read_result);
        fflush(stdout);
	}

    if (map_base != (void*)(-1)) {
		if(munmap(map_base, MAP_SIZE) == -1) FATAL;
		map_base = (void*)(-1);
	}

	if (map_base != (void*)(-1)) {
		if(munmap(map_base, MAP_SIZE) == -1) FATAL;
	}
	if (fd != -1) {
		close(fd);
	}

	return ret_val;

}
