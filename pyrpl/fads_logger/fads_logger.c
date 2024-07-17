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
#include <inttypes.h>
//#include <stdint.h>


#define FATAL do { fprintf(stderr, "Error at line %d, file %s (%d) [%s]\n", \
  __LINE__, __FILE__, errno, strerror(errno)); exit(1); } while(0)

#define MAP_SIZE 131072UL
#define MAP_MASK (MAP_SIZE - 1)

#define N_OUTPUT_PARAMETERS 5
#define INTENSITY_MAX_FACTOR 0.002441406

#define SAMPLE_RATE 125000
//#define SAMPLE_RATE 2

// (void*)(-1) is the MAP_FAILED return value of mmap
void* map_base = (void*)(-1);

int main(int argc, char **argv) {
//    printf("DEBUG | Starting Logger\n");
    int fd = -1;
    int ret_val = 0;


//    uint32_t address_base =   0x40600110;
    uint32_t address_base =   0x40600000;
    uint32_t output_offset =  0x00000200;
//    uint32_t output_offset =  0x00000300;
//    uint32_t address_base =   0x40110000;
//    uint32_t buffer_offset =  0x00010000;
//    uint32_t wp_address =     0x1000;
//    uint32_t buf_tail = 0x0;
//    uint32_t address;

    uint32_t output[N_OUTPUT_PARAMETERS];
    double intensity;
    double width;
    uint32_t last_id = 0;
    uint32_t address_alignment = 0x4;
//    uint32_t buffer_length = 0x10;
//    uint32_t n_buffer_filled;

    if((fd = open("/dev/mem", O_RDONLY)) == -1) FATAL;
//    printf("DEBUG | Mapping Memory\n");
    map_base = mmap(0, MAP_SIZE, PROT_READ, MAP_SHARED, fd, address_base & ~MAP_MASK);
    if(map_base == (void *) -1) FATAL;

    int i;
//    printf("DEBUG | Memory Mapped\n");

//    FILE *fp;
//    fp = fopen("test.log", "w");
//    printf("DEBUG | Starting Logging\n");

    while (1==1) {
        for ( i = 0; i < N_OUTPUT_PARAMETERS; ++i) {
            void* virt_addr = map_base + ((address_base + output_offset + (i * address_alignment)) & MAP_MASK);
            output[i] = *((volatile uint32_t *) virt_addr);
//            printf("DEBUG | %d %" PRIu32 "\n", i, output[i]);
        }

        intensity = (int32_t) output[1] * INTENSITY_MAX_FACTOR;
        width = (uint32_t) output[2] / (double) SAMPLE_RATE;

        if (last_id != output[0]) {
//            fprintf(fp, "%12u\t%12f\t%12d\n", output[0], (double) (output[1] * INTENSITY_MAX_FACTOR) / , output[2]);
            printf("%12u\t%12d\t%f\t%12u\t%f\t%3u\t%12u\n", output[0], output[1], intensity, output[2], width, output[3], output[4]);
//            printf("%12u\t%12d\t%12u\t%3u\t%12u\t%12u\n", output[0], output[1], output[2], output[3], output[4], output[5]);
//            printf("DEBUG | ID %" PRIu32 "\tIntensity %" PRIu32 "\tWidth %" PRIu32 "\tClassification %" PRIu32 "\tTime %" PRIu32 "\n", output[0]);
//            printf("DEBUG | ID %\tIntensity %\tWidth %\tClassification %\tTime %" PRIu32 PRIu32 PRIu32 PRIu32 PRIu32 "\n", output[0]);
//            printf("DEBUG | TIME %" PRIu32 "\n", output[4]);
        }

        last_id = output[0];


//        // Get current write pointer from FPGA
//        void* wp_virt_address = map_base + ((address_base + wp_address) & MAP_MASK);
//        uint32_t buf_head = 0;
//        buf_head = *((uint32_t *) wp_virt_address);
//
////        printf("ADDR: 0x%08x -> 0x%08x\n", wp_address, buf_head);
//
//        // Calculate buffer fill status
//        n_buffer_filled = buf_head - buf_tail + buffer_length - 1;
//
//        // Only check if reader (tail) caught up to writer (head, FPGA)
//        if (buf_head - buf_tail != 0) {
////        if (n_buffer_filled > 1) {
////        if (1 == 1) {
//
//            // Increment tail address (with wrap modulo for ring buffer)
//            buf_tail = (buf_tail + 1) % buffer_length;
//
//            // Build address from tail index and read out memory location
//            address = address_base + buffer_offset + (buf_tail * address_alignment);
//            void* virt_addr = map_base + (address & MAP_MASK);
//            uint32_t buf_read_result = 0;
//            buf_read_result = *((uint32_t *) virt_addr);
//            printf("BUF: 0x%08x Head: 0x%08x Tail: 0x%08x CUR ADDR: 0x%08x -> 0x%08x\n", n_buffer_filled, buf_head, buf_tail, address, buf_read_result);
//        }


        fflush(stdout);
	}

    if (map_base != (void*)(-1)) {
		if(munmap(map_base, MAP_SIZE) == -1) FATAL;
		map_base = (void*)(-1);
	}

	if (map_base != (void*)(-1)) {
		if(munmap(map_base, MAP_SIZE) == -1) FATAL;
	}

//	if (fp != -1) {
//	    close(fp);
//	}
	if (fd != -1) {
		close(fd);
	}

	return ret_val;

}
