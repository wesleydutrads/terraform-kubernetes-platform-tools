#!/usr/bin/env bash

if [ -d /home/linuxbrew/.linuxbrew/bin ]; then
  PATH="/home/linuxbrew/.linuxbrew/bin:${PATH}"
elif [ -d /opt/homebrew/bin ]; then
  PATH="/opt/homebrew/bin:${PATH}"
elif [ -d /usr/local/bin ]; then
  PATH="/usr/local/bin:${PATH}"
fi

export PATH
