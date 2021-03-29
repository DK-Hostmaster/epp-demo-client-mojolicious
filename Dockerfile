FROM debian:jessie
MAINTAINER jonasbn

RUN apt-get update -y
RUN apt-get install -y curl build-essential carton libxml2-dev libssl-dev libexpat1-dev

COPY . /usr/src/app
WORKDIR /usr/src/app
RUN carton install --deployment
RUN mkdir log

EXPOSE 3000

CMD carton exec morbo script/epp_demo_client
