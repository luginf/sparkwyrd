#!/bin/sh
# Sparkwyrd — sh/Tcl polyglot bootstrap
# The backslash at the end of this line is a Tcl line-continuation inside a comment \
_w=$(stty -g 2>/dev/null); trap '[ -n "$_w" ] && stty "$_w" 2>/dev/null' EXIT INT TERM; tclsh "$0" "$@"; exit $?
