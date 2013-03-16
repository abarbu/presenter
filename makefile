all: presenter

presenter: presenterlib-c.o presenter.o
	csc presenter.o presenterlib-c.o -o presenter -lX11 `imlib2-config --libs` -lavutil -lavformat -lavcodec -lz -lavutil -lm -lswscale

presenterlib-c.o: presenterlib-c.c
	gcc -Wall -d2 -std=gnu99 -c presenterlib-c.c

presenter.o: presenter.scm
	csc -M -d2 -S -c presenter.scm -O1
