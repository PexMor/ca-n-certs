#!/bin/bash

BD=$HOME/.config/squid/config
mkdir -p $BD

htpasswd -bc $BD/passwd username pass
htpasswd -b $BD/passwd u1 p1
htpasswd -b $BD/passwd u2 p2
htpasswd -b $BD/passwd u3 p3