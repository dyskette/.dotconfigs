#!/usr/bin/env bash

if which fnm &>/dev/null; then
  eval "$(fnm env --use-on-cd)"
  eval "$(fnm completions --shell bash)"
fi
