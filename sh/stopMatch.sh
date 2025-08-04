#!/bin/bash

skynet_pid=$(cat ../skynetMatch.pid)

kill -9 $skynet_pid

rm -f ../skynetMatch.pid
