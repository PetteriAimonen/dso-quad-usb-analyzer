# You can override PAWNCC by running with 'make PAWNCC=....'
PAWNCC ?= ../../QuadPawn/Compiler/bin/pawncc

all: usb.amx

clean:
	rm -f usb.amx

usb.amx: main.pawn *.pawn
	$(PAWNCC) -o$@ -d2 -v2 -V1 $<

deploy: usb.amx
	todrive /mnt/dso usb.amx
