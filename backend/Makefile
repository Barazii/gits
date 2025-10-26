.PHONY: build install clean

build:
	mkdir -p build
	cd build && cmake ..
	cd build && make

install:
	cd build && sudo make install

clean:
	rm -rf build
