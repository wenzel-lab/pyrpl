/* @brief This is a simple application for testing SPI communication on a RedPitaya
* @Author Luka Golinar <luka.golinar@redpitaya.com>
*
* (c) Red Pitaya  http://www.redpitaya.com
*
* This part of code is written in C programming language.
* Please visit http://en.wikipedia.org/wiki/C_(programming_language)
* for more details on the language used herein.
*/

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdbool.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <errno.h>
#include <string.h>
#include <linux/spi/spidev.h>
#include <linux/types.h>

/* Inline functions definition */
static int init_spi();
static int release_spi();
static int read_flash_id(int fd);
static int write_spi(char *write_data, int size);

/* Constants definition */
int spi_fd = -1;

// typedef adc_value_s adc_value;
// struct adc_value_s {
//     int address;
//     int value;
// }

// static bool is_adc_value_valid(adc_value adc_val){
//     if(adc_val.value < 0 || adc_val.value > 1024){
//         return false;
//     }
//     if (adc_val.address < 0 || adc_val.address > 7) {
//     return true;
// }

typedef struct spi_packet_s{
    int address;
    int value;
} spi_packet;

static bool is_spi_packet_valid(spi_packet spi_packet){
    if(spi_packet.address < 1 || spi_packet.address > 6){
        return true;
    }
    if(spi_packet.value < 0 || spi_packet.value > 1023){
        return false;
    }
    return true;
}



static char *spi_packet_to_char(spi_packet spi_packet){
    char *result = malloc(2*sizeof(char));

    /* Extract the address and value into four and ten bits respectively */
    int address_4bits = spi_packet.address & 0xF;
    int value_10bits = spi_packet.value & 0x3FF;

    /* Build the char */
    result[0] = (address_4bits << 4) | ((value_10bits >> 6) & 0xF);
    result[1] = ((value_10bits & 0x3F) << 2) | 0b01;

    return result;
}


static spi_packet* read_spi_packets_from_file(const char* filename, int *spi_packet_count){

    FILE *file = fopen(filename, "r");
    if (file == NULL) {
        perror("Error opening file");
        exit(1);
    }

    /* Count number of lines in file to allocate correct amount of memory */
    int line_count = 0;
    char line[100];
    while (fgets(line, sizeof line, file) != NULL) {
        line_count++;
    }
    rewind(file);

    spi_packet* spi_packets = malloc(line_count * sizeof(spi_packet));

    int i = 0;
    while (fscanf(file, "%d\t%d\n", &spi_packets[i].address, &spi_packets[i].value) == 2) {
        i++;
    }

    fclose(file);
    *spi_packet_count = i;

    for(int i = 0; i < *spi_packet_count; i++){
        if(!is_spi_packet_valid(spi_packets[i])){
            fprintf(stderr, "Packet at index %d is not valid!\n", i);
            free(spi_packets);
            return NULL;
        }
    }

    return spi_packets;
}



int main(void){

    /* Sample data */
    // char *data = "0b1001010010001101";
    // char *data = "He";



    // spi_packet packet = {
    //     .address = 5,
    //     .value = 657
    // };
    // if (!is_spi_packet_valid(packet)) {
    //     return -1;
    // }
    // char *data = spi_packet_to_char(packet);

    /* Init the spi resources */
    if(init_spi() < 0){
        printf("Initialization of SPI failed. Error: %s\n", strerror(errno));
        return -1;
    }

    int spi_packet_count = 0;
    int *spi_packet_count_ptr = &spi_packet_count;
    spi_packet *spi_packets = read_spi_packets_from_file("bias_values.tsv", spi_packet_count_ptr);
    if(spi_packets == NULL){
        printf("Failed to read spi packets from file!\n");
        return -1;
    }

    for(int i=0; i<spi_packet_count; i++){
        char *data = spi_packet_to_char(spi_packets[i]);

        /* Write some sample data */
        if(write_spi(data, 2) < 0){
            printf("Write to SPI failed. Error: %s\n", strerror(errno));
            return -1;
        }
        free(data);

        /* Read flash ID and some sample loopback data */
        if(read_flash_id(spi_fd) < 0){
            printf("Error reading from SPI bus : %s\n", strerror(errno));
            return -1;
        }
    }


    /* Release resources */
    if(release_spi() < 0){
        printf("Relase of SPI resources failed, Error: %s\n", strerror(errno));
        return -1;
    }

    return 0;
}

static int init_spi(){

    /* MODES: mode |= SPI_LOOP;
    *        mode |= SPI_CPHA;
    *        mode |= SPI_CPOL;
    *                 mode |= SPI_LSB_FIRST;
    *        mode |= SPI_CS_HIGH;
    *        mode |= SPI_3WIRE;
    *        mode |= SPI_NO_CS;
    *        mode |= SPI_READY;
    *
    * multiple possibilities possible using | */
    int mode = 0;

    /* Opening file stream */
    spi_fd = open("/dev/spidev1.0", O_RDWR | O_NOCTTY);

    if(spi_fd < 0){
        printf("Error opening spidev0.1. Error: %s\n", strerror(errno));
        return -1;
    }

    /* Setting mode (CPHA, CPOL) */
    if(ioctl(spi_fd, SPI_IOC_WR_MODE, &mode) < 0){
        printf("Error setting SPI_IOC_RD_MODE. Error: %s\n", strerror(errno));
        return -1;
    }

    /* Setting SPI bus speed */
    int spi_speed = 1000000;

    if(ioctl(spi_fd, SPI_IOC_WR_MAX_SPEED_HZ, &spi_speed) < 0){
        printf("Error setting SPI_IOC_WR_MAX_SPEED_HZ. Error: %s\n", strerror(errno));
        return -1;
    }

    return 0;
}

static int release_spi(){

    /* Release the spi resources */
    close(spi_fd);

    return 0;
}

/* Read data from the SPI bus */
static int read_flash_id(int fd){

    int size = 2;

    /*struct spi_ioc_transfer {
        __u64           tx_buf;
        __u64           rx_buf;

        __u32           len;
        __u32           speed_hz;

        __u16           delay_usecs;
        __u8            bits_per_word;
        __u8            cs_change;
        __u32           pad;
    }*/
    /* If the contents of 'struct spi_ioc_transfer' ever change
    * incompatibly, then the ioctl number (currently 0) must change;
    * ioctls with constant size fields get a bit more in the way of
    * error checking than ones (like this) where that field varies.
    *
    * NOTE: struct layout is the same in 64bit and 32bit userspace.*/
    struct spi_ioc_transfer xfer[size];

    unsigned char           buf0[1];
    unsigned char           buf1[3];
    int                     status;

    memset(xfer, 0, sizeof xfer);

    /* RDID command */
    buf0[0] = 0x9f;
    /* Some sample data */
    buf1[0] = 0x01;
    buf1[1] = 0x23;
    buf1[2] = 0x45;

    /* RDID buffer */
    xfer[0].tx_buf = (__u64)((__u32)buf0);
    xfer[0].rx_buf = (__u64)((__u32)buf0);
    xfer[0].len = 1;

    /* Sample loopback buffer */
    xfer[1].tx_buf = (__u64)((__u32)buf1);
    xfer[1].rx_buf = (__u64)((__u32)buf1);
    xfer[1].len = 3;

    /* ioctl function arguments
    * arg[0] - file descriptor
    * arg[1] - message number
    * arg[2] - spi_ioc_transfer structure
    */
    status = ioctl(fd, SPI_IOC_MESSAGE(2), xfer);
    if (status < 0) {
        perror("SPI_IOC_MESSAGE");
        return -1;
    }

    /* Print read buffer */
    for(int i = 0; i < 3; i++){
        printf("Buffer: %d\n", buf1[i]);
    }

    return 0;
}

char *test_string = "Hello World";

/* Write data to the SPI bus */
static int write_spi(char *write_buffer, int size){

    int write_spi = write(spi_fd, write_buffer, size);

    if(write_spi < 0){
        printf("Failed to write to SPI. Error: %s\n", strerror(errno));
        return -1;
    }

    return 0;
}