FROM debian:jessie

RUN apt-get update -y
RUN apt-get install -y curl build-essential carton libxml2-dev libssl-dev libexpat1-dev

COPY cpanfile.snapshot /usr/src/app/cpanfile.snapshot
COPY cpanfile /usr/src/app/cpanfile

WORKDIR /usr/src/app
RUN carton install --deployment
RUN mkdir log

COPY . /usr/src/app

EXPOSE 3000

CMD carton exec morbo script/epp_demo_client
