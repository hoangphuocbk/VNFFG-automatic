#!/bin/bash
while true; do echo -e "HTTP/1.0 200 OK\r\n\r\nWelcome to $(hostname)" | sudo nc -l -p 80 ; done&

