run: all

all: spi_test

spi_test: spi_test.o
	gcc spi_test.o -o spi_test

spi_test.o: spi_test.c
	gcc -O3 -Wall -c spi_test.c

clean:
	rm -rf *.o

