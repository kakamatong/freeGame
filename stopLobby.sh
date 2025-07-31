#!/bin/bash

skynet_pid=$(cat skynetLobby.pid)

kill -9 $skynet_pid

rm -f skynetLobby.pid