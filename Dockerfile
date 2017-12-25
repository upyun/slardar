FROM centos:6

RUN yum -y update && yum clean all
RUN yum -y install epel-release; yum clean all
RUN yum -y install wget gcc gcc-c++ patch zlib-devel perl && yum clean all

ADD patches /src/patches
ADD util /src/util
ADD Makefile /src/
ADD nginx /src/nginx

EXPOSE 8080 1995

RUN cd /src && make configure && make && make install && rm -fr /src

CMD ["/usr/local/slardar/nginx/sbin/nginx", "-g", "daemon off;"]
