#!/bin/bash

skynet_pid=$(cat skynetGame.pid)

kill -9 $skynet_pid

rm -f skynetGame.pid