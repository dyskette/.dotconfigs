# WezTerm shell integration: OSC 133 semantic zones, OSC 7 cwd reporting and
# the user vars the status bar reads.
#
# Enables, on the WezTerm side:
#   - LEADER y      copy the entire output of the last command
#   - LEADER { }    jump between shell prompts in the scrollback
#   - triple-click  select a whole command's output rather than a screen line
#   - new splits    inherit the current directory
#   - status bar    git branch and dirty count, at no rendering cost
#
# Must be sourced after starship.sh, which owns PS1 and PROMPT_COMMAND. The
# bashrc.d loader sources in glob order, and "w" sorts after "s".

# Confine every effect to interactive WezTerm sessions: nothing here should
# alter a script, an ssh session or another terminal.
[[ $- == *i* ]] || return 0
[[ -n "$WEZTERM_PANE" ]] || return 0
[[ -n "$__WF_SI_LOADED" ]] && return 0
__WF_SI_LOADED=1

__wf_osc() { printf '\033]%s\007' "$1" >/dev/tty; }

# Publishes a value WezTerm can read back with pane:get_user_vars().
__wf_set_user_var() {
	printf '\033]1337;SetUserVar=%s=%s\007' \
		"$1" "$(printf '%s' "$2" | base64 | tr -d '\n')" >/dev/tty
}

# Branch and dirty count for the status bar. Computed here rather than in the
# WezTerm config because the config would have to shell into WSL on every
# status tick; at the prompt it is one cheap call in the right place already.
__wf_git_status() {
	git rev-parse --is-inside-work-tree &>/dev/null || return 0

	local branch dirty
	branch=$(git symbolic-ref --short -q HEAD 2>/dev/null) ||
		branch=$(git rev-parse --short HEAD 2>/dev/null) || return 0

	dirty=$(git status --porcelain 2>/dev/null | wc -l)
	if [[ "$dirty" -gt 0 ]]; then
		printf '%s ✎%s' "$branch" "$dirty"
	else
		printf '%s' "$branch"
	fi
}

__wf_precmd() {
	# Starship records the real command status before its own prompt logic
	# runs; without it $? here would be the status of the previous
	# PROMPT_COMMAND entry rather than the user's command.
	local cmd_status=${STARSHIP_CMD_STATUS:-$?}

	__wf_osc "133;D;${cmd_status}"
	__wf_osc "133;A"

	# OSC 7: lets WezTerm track the directory, which is what makes a new
	# split open where the current one is.
	__wf_osc "7;file://${HOSTNAME}${PWD// /%20}"

	__wf_set_user_var "WF_GIT" "$(__wf_git_status)"

	# Starship rewrites PS1 every prompt, so the input-start marker is
	# re-appended each time rather than once at startup.
	case "$PS1" in
	*'133;B'*) ;;
	*) PS1="${PS1}"'\[\e]133;B\a\]' ;;
	esac
}

# Output-start marker. PS0 is expanded after a command is read and before it
# runs, which is exactly preexec — and unlike a DEBUG trap it composes with
# whatever else is installed. A sourced file cannot read the caller's DEBUG
# trap anyway: bash resets it for the duration of the source.
case "$PS0" in
*'133;C'*) ;;
*) PS0="${PS0}"'\e]133;C\a' ;;
esac

# Append, never prepend: this has to run after starship has set PS1.
if [[ ${PROMPT_COMMAND@a} == *a* ]]; then
	PROMPT_COMMAND+=(__wf_precmd)
else
	PROMPT_COMMAND="${PROMPT_COMMAND:+${PROMPT_COMMAND}$'\n'}__wf_precmd"
fi
