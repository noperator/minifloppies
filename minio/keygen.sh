#!/bin/sh

echo -n 'ACCESS KEY: '
base64 /dev/urandom | tr -d '/+' | head -c 20 | tr '[:lower:]' '[:upper:]'
echo
echo -n 'SECRET KEY: '
base64 /dev/urandom | tr -d '/+' | head -c 40
echo
