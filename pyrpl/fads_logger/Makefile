run: all

all: fads_logger

fads_logger: fads_logger.o
	gcc fads_logger.o -o fads_logger

fads_logger.o: fads_logger.c
	gcc -O3 -Wall -c fads_logger.c

clean:
	rm -rf *.o

