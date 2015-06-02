CC=cc 

all:	clean mywait trigger create_sem install clean_again 
mywait:	mywait.o
	cc -o mywait mywait.o 
trigger:	trigger.o
	cc -o trigger trigger.o
create_sem:	create_sem.o
	cc -o create_sem create_sem.o
install:
	cp mywait trigger create_sem ../
	cp mywait trigger create_sem ../misc
clean:
	rm -fr *.o mywait trigger create_sem 
clean_again:
	rm -fr *.o
