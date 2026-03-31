all: vmcache

vmcache: vmcache.cpp RandomGenerator.hpp ZipfianGenerator.hpp
	g++ -DNDEBUG -O3 -std=c++20 -g -fnon-call-exceptions -fasynchronous-unwind-tables vmcache.cpp -o vmcache

clean:
	rm vmcache