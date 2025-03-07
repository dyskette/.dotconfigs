#!/usr/bin/env bash

dotnetdir="$HOME/.dotnet"
if [ -d "$dotnetdir" ]; then
	export DOTNET_ROOT="$dotnetdir"
	export PATH=$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools
fi
unset dotnetdir

if which dotnet &>/dev/null; then
	# bash parameter completion for the dotnet CLI
	function _dotnet_bash_complete()
	{
	  local cur="${COMP_WORDS[COMP_CWORD]}" IFS=$'\n' # On Windows you may need to use use IFS=$'\r\n'
	  local candidates

	  read -d '' -ra candidates < <(dotnet complete --position "${COMP_POINT}" "${COMP_LINE}" 2>/dev/null)

	  read -d '' -ra COMPREPLY < <(compgen -W "${candidates[*]:-}" -- "$cur")
	}

	complete -f -F _dotnet_bash_complete dotnet
fi
