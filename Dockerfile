# Use the official Ubuntu 20.04 base image
FROM ubuntu:20.04

# Set the working directory
WORKDIR /app

# Install required packages
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y git make sudo build-essential python3 python3-pip wget clang llvm \
    zip cmake autoconf automake curl strace ninja-build pkg-config \
    libglib2.0-dev libprocps-dev libboost-all-dev libssl-dev gcc-plugin-dev  && \
    apt-get clean && \
    ln -s /usr/bin/python3 /usr/bin/python && \
    rm -rf /var/lib/apt/lists/*

# Install modern LLVM for AFL++ (AFL++ requires LLVM >= 13)
RUN wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add - && \
    echo "deb http://apt.llvm.org/focal/ llvm-toolchain-focal-14 main" >> /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y clang-14 llvm-14-dev llvm-14-tools lld-14 && \
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-14 100 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-14 100 && \
    update-alternatives --install /usr/bin/llvm-config llvm-config /usr/bin/llvm-config-14 100

# install AFL and AFL++
RUN git clone https://github.com/google/AFL.git
RUN git clone https://github.com/AFLplusplus/AFLplusplus 
RUN pip install psutil
RUN cd AFL && export AFL_NO_X86=1 && make && make -C llvm_mode
RUN cd AFLplusplus && export LLVM_CONFIG=llvm-config-14 && make distrib && sudo make install

COPY OSS-Fuzz ./OSS-Fuzz/
COPY confirmed_bugs.txt ./

# Copy the contents of OSS-Fuzz into the container
COPY OSS-Fuzz ./OSS-Fuzz/
RUN cd OSS-Fuzz && git clone https://github.com/google/oss-fuzz 

# export environ vars BOIAN_AFL and BOIAN_AFLPP as AFL and AFL++ path
ENV BOIAN_AFL=/app/AFL/
ENV BOIAN_AFLPP=/app/AFLplusplus/

WORKDIR /app/OSS-Fuzz

# call script create_fuzzing_drivers.sh
RUN ./create_fuzzing_drivers.sh 

# Uncomment below if you want to test on smaller set of projects from OSS-Fuzz that begin on letter 'e'
#RUN cd oss-fuzz/projects && find . -maxdepth 1 -type d ! -name 'e*' ! -name '.' -exec rm -r {} +

# prepare OSS-Fuzz targets for fuzzing
RUN pip3 install numpy timeout_decorator
RUN python3 compile.py 
RUN python3 get_interesting.py


# Compile the schedulers
COPY Schedulers /app/Schedulers/
WORKDIR /app/Schedulers
RUN make

# export enviros to set the schedulers
ENV BOIAN_SCHEDULER=boian
ENV BOIAN_USE_CPUS=3          
ENV BOIAN_MINUTES_PER_TARGET=15  
ENV BOIAN_FUZZ_TARGETS=/app/OSS-Fuzz/fuzz_targets/

WORKDIR /app/Schedulers/run

CMD ["/bin/bash"]
