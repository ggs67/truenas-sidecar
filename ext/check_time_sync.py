#!/usr/bin/env bash

import ntplib
from time import ctime

ntpc = ntplib.NTPClient()
ntp  = ntpc.request('nas1.home.gloesener.lu')
local=ctime()
remote=ctime(ntp.tx_time)

print(f"offset: {ntp.offset}")
print(f"version: {ntp.version}")
print(f"local: {local}")
print(f"remote: {remote}")
