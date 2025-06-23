#!/bin/bash

skynet_pid=$(cat skynet.pid)

kill -9 $skynet_pid

rm -f skynet.pid