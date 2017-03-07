# -*- coding: utf-8 -*-

## Daniel Clerc <daniel@netzguerilla.net> 03/2017

from telnetlib import Telnet
from time import sleep
import yaml

with open("../config.yml","r") as f:
    config = yaml.load(f.read()).get('cluster')

HOST = config.get('host')
PORT = int(config.get('port'))
USER = config.get('user')
PASS = config.get('pass')

tn = Telnet(HOST,PORT)
tn.read_until("login: ")
tn.write(USER+"\n")
tn.read_until("password: ")
tn.write(PASS+"\n")
sleep(15)
while True:
    sleep(1)
    print(tn.read_eager())

