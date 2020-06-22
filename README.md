# tinysoc
My first SoC implemented for the TinyFPGA BX

# Development environment
I build and develop the core with this container https://github.com/nevercast/docker-fusesoc-tinyfpga 

Using a container helps me keep the differences across my machines minimum.

# Building
Provided that you have Docker and Python3 installed, you should be able to use build.py to build the 
firmware image, and program it. The quickest way to flash tinysoc on to your TinyFPGA BX is:

```
./build.py build test program
```

This will build the image, test it with iVerilog, and flash the device.