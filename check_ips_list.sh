#!/bin/bash

BASE_IP=10.224.140
START=97
END=126

## save $START, just in case if we need it later ##
i=$START
while [[ $i -le $END ]]; do
	echo "$i"
	ping -c 2 $IP &> /dev/null
        ((i = i + 1))
done

ping -c 2 $BASE_IP.$i &> /dev/null