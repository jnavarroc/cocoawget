#!/bin/bash

#http://developer.apple.com/technotes/tn2005/tn2137.html


#./wget -c http://ftp.gnu.org/pub/gnu/wget/wget-1.10.2.tar.gz
#tar xvfz wget-1.10.2.tar.gz
#cd wget-1.10.2
./wget -c http://ftp.gnu.org/pub/gnu/wget/wget-1.11.2.tar.gz
tar xvfz wget-1.11.2.tar.gz
cd wget-1.11.2


#export CFLAGS="-Os -isysroot /Developer/SDKs/MacOSX10.4u.sdk -arch i386 -arch ppc"  
#export LDFLAGS="-Wl,-syslibroot,/Developer/SDKs/MacOSX10.4u.sdk" 
#./configure --disable-dependency-tracking
./configure 
make
cp src/wget ../
cd ../
./wget --version
file wget
