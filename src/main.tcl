# Sparkwyrd — entry-point dispatcher (included last by the Makefile build)
#
# Mode selection:
#   (no args)          → print quick usage hint and exit (safe for tab completion)
#   --gui [file.ipt]   → launch GUI
#   --cli [options]    → CLI mode
#   -n / -t / --html … → auto-select CLI mode (recognised CLI flags)
#   file.ipt only      → GUI mode (open file)

proc sparkwyrd_dispatch {} {
    global argv

    set cli_flags {-n -t --html --sep --list --version --help}
    set mode      ""
    set rest      {}

    foreach arg $argv {
        switch -- $arg {
            --gui   { set mode gui }
            --cli   { set mode cli }
            default { lappend rest $arg }
        }
    }
    set argv $rest

    # No arguments at all: print a one-line hint and exit immediately.
    # This prevents bash/zsh completion from hanging while trying to
    # execute the script during tab-completion probing.
    if {$mode eq "" && [llength $rest] == 0} {
        set name [file tail [info script]]
        puts "Usage: $name --gui \[file.ipt\]   or   $name --cli \[options\] file.ipt"
        exit 0
    }

    # Auto-detect from remaining args when no explicit --gui/--cli
    if {$mode eq ""} {
        set mode gui
        foreach arg $rest {
            if {$arg in $cli_flags || [string match "-*" $arg]} {
                set mode cli
                break
            }
        }
    }

    if {$mode eq "gui"} {
        if {[catch {gui_main} err]} {
            puts stderr "Cannot start GUI: $err"
            puts stderr "Try: [file tail [info script]] --cli \[options\] file.ipt"
            exit 1
        }
    } else {
        cli_main
    }
}

sparkwyrd_dispatch
