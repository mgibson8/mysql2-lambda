ARG IMAGE_ARCH
FROM public.ecr.aws/lambda/ruby:3.2-$IMAGE_ARCH

RUN yum groupinstall -y development && \
  yum install -d1 -y \
  yum \
  tar \
  gzip \
  unzip \
  python3 \
  jq \
  grep \
  curl \
  make \
  rsync \
  binutils \
  gcc-c++ \
  procps \
  libgmp3-dev \
  zlib1g-dev \
  libmpc-devel \
  python3-devel \
  && yum clean all

RUN gem update --system --no-document

# Install AWS CLI
ARG AWS_CLI_ARCH
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-$AWS_CLI_ARCH.zip" -o "awscliv2.zip" && unzip awscliv2.zip && ./aws/install && rm awscliv2.zip && rm -rf ./aws

# Install SAM CLI in a dedicated Python virtualenv
ARG SAM_CLI_VERSION

RUN curl -L "https://github.com/awslabs/aws-sam-cli/archive/v$SAM_CLI_VERSION.zip" -o "samcli.zip" && \
  unzip samcli.zip && python3 -m venv /usr/local/opt/sam-cli && \
  /usr/local/opt/sam-cli/bin/pip3 --no-cache-dir install -r ./aws-sam-cli-$SAM_CLI_VERSION/requirements/base.txt && \
  /usr/local/opt/sam-cli/bin/pip3 --no-cache-dir install ./aws-sam-cli-$SAM_CLI_VERSION && \
  rm samcli.zip && rm -rf aws-sam-cli-$SAM_CLI_VERSION

ENV PATH=$PATH:/usr/local/opt/sam-cli/bin

# Wheel is required by SAM CLI to build libraries like cryptography. It needs to be installed in the system
# Python for it to be picked up during `sam build`
RUN pip3 install wheel

ENV LANG=en_US.UTF-8

# COPY ATTRIBUTION.txt /

# # Compatible with initial base image
# ENTRYPOINT []
# CMD ["/bin/bash"]

WORKDIR /build

ARG MYSQL_VERSION

ENV PATH=/opt/bin:$PATH
ENV LD_LIBRARY_PATH=/opt/lib:/opt/lib64:$LD_LIBRARY_PATH
ENV MYSQL_VERSION=$MYSQL_VERSION

RUN echo '== patchelf =='
RUN git clone https://github.com/NixOS/patchelf.git && \
  cd ./patchelf && \
  git checkout 0.11 && \
  ./bootstrap.sh && \
  ./configure --prefix=/opt && \
  make && \
  make install

RUN echo '== MySQL Connector =='
RUN yum install -y cmake
RUN curl -L https://downloads.mysql.com/archives/get/p/19/file/mysql-connector-c-6.1.11-src.tar.gz > mysql-connector-c-6.1.11-src.tar.gz && \
  tar -xf mysql-connector-c-6.1.11-src.tar.gz && \
  cd mysql-connector-c-6.1.11-src && \
  cmake . -DCMAKE_BUILD_TYPE=Release && \
  make && \
  make install

RUN echo '== Install Mysql2 Gem =='
RUN rm -rf /usr/local/mysql/lib/libmysqlclient.so* && \
  gem install mysql2 \
  -v $MYSQL_VERSION \
  -- --with-mysql-dir=/usr/local/mysql

RUN echo '== Patch MySQL2 Gem =='
RUN patchelf --add-needed librt.so.1 \
  "/var/lang/lib/ruby/gems/3.2.0/gems/mysql2-${MYSQL_VERSION}/lib/mysql2/mysql2.so" && \
  patchelf --add-needed libstdc++.so.6 \
  "/var/lang/lib/ruby/gems/3.2.0/gems/mysql2-${MYSQL_VERSION}/lib/mysql2/mysql2.so"

RUN echo '== Share Files =='
RUN mkdir -p /build/share && \
  cp -r "/var/lang/lib/ruby/gems/3.2.0/gems/mysql2-${MYSQL_VERSION}"/* /build/share && \
  rm -rf /build/share/ext \
  /build/share/README.md \
  /build/share/support

ENTRYPOINT ["/bin/bash", "-l", "-c"]