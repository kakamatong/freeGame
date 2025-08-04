#!/bin/bash

skynet_pid=$(cat ../skynetAuth.pid)

kill -9 $skynet_pid

rm -f ../skynetAuth.pid
