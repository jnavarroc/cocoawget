#!/bin/bash

#http://developer.apple.com/technotes/tn2005/tn2137.html

./wget -c http://ftp.gnu.org/gnu/wget/wget-1.11.4.tar.gz
tar xvfz wget-1.11.4.tar.gz
cd wget-1.11.4

export CFLAGS="-Os -isysroot /Developer/SDKs/MacOSX10.5.sdk -arch i386 -arch ppc"  
export LDFLAGS="-Wl,-syslibroot,/Developer/SDKs/MacOSX10.5.sdk" 
./configure --disable-dependency-tracking
make
cp src/wget ../
cd ../
./wget --version
file wget
