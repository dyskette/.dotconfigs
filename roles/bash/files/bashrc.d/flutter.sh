#!/usr/bin/env bash

flutterDir="$HOME/.local/opt/flutter/bin"
if [ -d "$flutterDir" ]; then
	export PATH=$PATH:$flutterDir
fi
unset flutterDir
