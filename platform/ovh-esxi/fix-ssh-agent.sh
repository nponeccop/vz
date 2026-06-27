#!/bin/sh
# fix-ssh-agent.sh — point the shell at the live forwarded SSH agent socket.
# The socket path rotates whenever the tmux session is reattached; this finds the
# newest one, updates the tmux environment, and prints an export for the current shell.
#
# Usage:  eval "$(./fix-ssh-agent.sh)"
SOCK=$(ls -t "$HOME"/.ssh/agent/s.* /tmp/ssh-*/agent.* 2>/dev/null | head -1)

[ -n "$SOCK" ] || { echo "No SSH agent socket found" >&2; exit 1; }
echo "Found: $SOCK" >&2

if [ -n "${TMUX:-}" ]; then
    tmux setenv SSH_AUTH_SOCK "$SOCK"
    echo "Updated tmux environment" >&2
fi

echo "export SSH_AUTH_SOCK=$SOCK"
