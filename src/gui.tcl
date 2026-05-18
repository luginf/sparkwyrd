#!/usr/bin/env wish
# Sparkwyrd — Tk GUI

set script_dir [file normalize [file dirname [info script]]]
source [file join $script_dir engine.tcl]

# ============================================================
# GLOBAL STATE
# ============================================================
set ::current_parsed {}
set ::current_file   ""
set ::reps_count     1
set ::status_msg     "Welcome to Sparkwyrd — open an .ipt file to begin"
set ::current_theme  "sepia"

# ============================================================
# THEME PALETTES
# ============================================================
array set ::themes {}

set ::themes(light) {
    bg         #f0f0f0
    bg2        #fafafa
    bg_tb      #ececec
    fg         #1a1a1a
    fg2        #666666
    fg_link    #0055cc
    sep        #cccccc
    out_bg     #ffffff
    out_fg     #111111
    out_title  #1a1a2e
    out_sep    #bbbbbb
    out_h1     #1a1a2e
    out_h2     #2a2a6e
    out_h3     #3a3a7e
    out_code_bg #f0f0f0
    btn_bg     #dcdcdc
    btn_fg     #1a1a1a
    btn_go_bg  #3a7d44
    btn_go_fg  #ffffff
    sel_bg     #3a7d44
    sel_fg     #ffffff
}

set ::themes(dark) {
    bg         #2b2b2b
    bg2        #242424
    bg_tb      #333333
    fg         #e0e0e0
    fg2        #888888
    fg_link    #6699ff
    sep        #444444
    out_bg     #1e1e1e
    out_fg     #d4d4d4
    out_title  #c8b97a
    out_sep    #444444
    out_h1     #c8b97a
    out_h2     #9ab8d8
    out_h3     #88aa88
    out_code_bg #2a2a2a
    btn_bg     #3c3c3c
    btn_fg     #e0e0e0
    btn_go_bg  #2e6636
    btn_go_fg  #ffffff
    sel_bg     #264f78
    sel_fg     #ffffff
}

set ::themes(sepia) {
    bg         #f5efe0
    bg2        #faf6ee
    bg_tb      #ede5d0
    fg         #3b2e1e
    fg2        #7a6248
    fg_link    #8b4513
    sep        #c8b89a
    out_bg     #fdf6e3
    out_fg     #3b2e1e
    out_title  #5c3d1e
    out_sep    #c8b89a
    out_h1     #5c3d1e
    out_h2     #7a4f28
    out_h3     #8b5e32
    out_code_bg #ede5d0
    btn_bg     #d8c9a8
    btn_fg     #3b2e1e
    btn_go_bg  #7a4f28
    btn_go_fg  #fdf6e3
    sel_bg     #c8a878
    sel_fg     #1a0a00
}

proc T {key} {
    return [dict get $::themes($::current_theme) $key]
}

# ============================================================
# THEME APPLICATION
# ============================================================
proc apply_theme {{theme ""}} {
    if {$theme ne ""} { set ::current_theme $theme }

    # Tk option database — applies to future widgets
    option add *Background          [T bg]      interactive
    option add *Foreground          [T fg]      interactive
    option add *Button.Background   [T btn_bg]  interactive
    option add *Button.Foreground   [T btn_fg]  interactive
    option add *Label.Background    [T bg]      interactive
    option add *Label.Foreground    [T fg]      interactive
    option add *Entry.Background    [T out_bg]  interactive
    option add *Entry.Foreground    [T out_fg]  interactive
    option add *Spinbox.Background  [T out_bg]  interactive
    option add *Spinbox.Foreground  [T out_fg]  interactive
    option add *selectBackground    [T sel_bg]  interactive
    option add *selectForeground    [T sel_fg]  interactive

    if {![winfo exists .tb]} return

    # Toolbar
    .tb configure -bg [T bg_tb]
    foreach w {.tb.open .tb.lrep .tb.theme_lbl} {
        catch { $w configure -bg [T bg_tb] -fg [T fg] -activebackground [T bg] }
    }
    catch { .tb.theme_mb configure -bg [T bg_tb] -fg [T fg] \
                -activebackground [T bg] -activeforeground [T fg] }
    .tb.sep1 configure -bg [T sep]
    .tb.go configure -bg [T btn_go_bg] -fg [T btn_go_fg] \
        -activebackground [T btn_go_bg]
    .tb.reps configure -bg [T out_bg] -fg [T out_fg] \
        -insertbackground [T out_fg]

    # Left panel
    .left configure -bg [T bg2]
    foreach w {.left.t1 .left.t2 .left.t3 .left.hd .left.mr} {
        catch { $w configure -bg [T bg2] -fg [T fg] }
    }
    .left.fname configure -bg [T bg2] -fg [T fg_link]
    .left.sep  configure -bg [T sep]
    .left.sep2 configure -bg [T sep]
    .left.tables configure -bg [T bg2] -fg [T fg2] \
        -selectbackground [T sel_bg] -selectforeground [T sel_fg] \
        -activestyle underline -highlightcolor [T sel_bg]
    .left.sb configure -bg [T bg2] -troughcolor [T bg]

    # Output area
    .right configure -bg [T out_bg]
    .right.nb.gen.out configure -bg [T out_bg] -fg [T out_fg] \
        -insertbackground [T out_fg] \
        -selectbackground [T sel_bg] -selectforeground [T sel_fg]
    .right.nb.gen.sb configure -bg [T bg] -troughcolor [T bg2]

    # Text widget tags
    .right.nb.gen.out tag configure ttitle \
        -font {Georgia 15 bold} -foreground [T out_title] -spacing3 4
    .right.nb.gen.out tag configure tsep \
        -foreground [T out_sep]
    .right.nb.gen.out tag configure tbody \
        -font {Georgia 12} -foreground [T out_fg] -spacing1 2 -spacing3 2
    .right.nb.gen.out tag configure tbold \
        -font {Georgia 12 bold} -foreground [T out_fg]
    .right.nb.gen.out tag configure titalic \
        -font {Georgia 12 italic} -foreground [T out_fg]
    .right.nb.gen.out tag configure tunderline \
        -font {Georgia 12} -underline 1 -foreground [T out_fg]
    .right.nb.gen.out tag configure tbold_italic \
        -font {Georgia 12 bold italic} -foreground [T out_fg]
    .right.nb.gen.out tag configure th1 \
        -font {Georgia 16 bold} -foreground [T out_h1] -spacing3 6
    .right.nb.gen.out tag configure th2 \
        -font {Georgia 14 bold} -foreground [T out_h2] -spacing3 4
    .right.nb.gen.out tag configure th3 \
        -font {Georgia 13 bold} -foreground [T out_h3] -spacing3 2
    .right.nb.gen.out tag configure tcode \
        -font {TkFixedFont 11} -foreground [T out_fg] \
        -background [T out_code_bg]

    # Editor theme
    editor_apply_theme

    # Status bar
    .st configure -bg [T bg_tb]
    .st.msg configure -bg [T bg_tb] -fg [T fg2]

    .pw configure -bg [T sep]
}

# ============================================================
# UI CONSTRUCTION
# ============================================================
proc build_ui {} {
    wm title . "Sparkwyrd"
    wm geometry . "920x620"
    wm minsize . 640 400

    # ---- Toolbar ----
    frame .tb -relief flat -bd 0
    pack .tb -fill x -side top

    button .tb.open -text "Open..." -command cmd_open \
        -relief flat -padx 10 -pady 5 -cursor hand2
    frame .tb.sep1 -width 1
    label  .tb.lrep -text "Reps:"
    spinbox .tb.reps -from 1 -to 999 -width 4 \
        -textvariable ::reps_count \
        -validate key -validatecommand {string is integer %P}
    button .tb.go -text "  Go" -command cmd_generate \
        -relief flat -padx 14 -pady 5 \
        -font {TkDefaultFont 10 bold} -cursor hand2

    # Theme selector (right side)
    label .tb.theme_lbl -text "Theme:"
    menubutton .tb.theme_mb -textvariable ::current_theme \
        -relief raised -padx 8 -pady 4 -width 8 -cursor hand2
    menu .tb.theme_mb.m -tearoff 0
    foreach th {light dark sepia} {
        .tb.theme_mb.m add command -label $th \
            -command [list apply_theme $th]
    }
    .tb.theme_mb configure -menu .tb.theme_mb.m

    pack .tb.open  -side left -padx {6 2} -pady 4
    pack .tb.sep1  -side left -padx 4 -pady 4 -fill y
    pack .tb.lrep     -side left -padx {4 2} -pady 4
    pack .tb.reps  -side left -padx 2 -pady 4
    pack .tb.go    -side left -padx 6 -pady 4
    pack .tb.theme_mb  -side right -padx 6 -pady 4
    pack .tb.theme_lbl -side right -padx {4 0} -pady 4

    frame .tb_sep -height 1
    pack .tb_sep -fill x -side top

    # ---- Main area ----
    panedwindow .pw -orient horizontal -sashwidth 5 -sashrelief flat
    pack .pw -fill both -expand 1

    # Left panel
    frame .left -width 210
    pack propagate .left 0

    label .left.t1 -text "Active file" \
        -font {TkDefaultFont 9 bold} -anchor w
    label .left.fname -textvariable ::ui_fname \
        -wraplength 195 -justify left -anchor w
    frame .left.sep -height 1
    label .left.t2 -text "Header" \
        -font {TkDefaultFont 9 bold} -anchor w
    label .left.hd -textvariable ::ui_header \
        -wraplength 195 -justify left -anchor w
    label .left.mr -textvariable ::ui_maxreps \
        -wraplength 195 -justify left -anchor w
    frame .left.sep2 -height 1
    label .left.t3 -text "Tables" \
        -font {TkDefaultFont 9 bold} -anchor w
    listbox .left.tables -width 22 -height 14 \
        -relief flat -font {TkFixedFont 9} \
        -selectmode single -highlightthickness 1
    scrollbar .left.sb -command {.left.tables yview} -width 8
    .left.tables configure -yscrollcommand {.left.sb set}

    # Bind click on table to jump to it in editor
    bind .left.tables <<ListboxSelect>> {
        set idx [.left.tables curselection]
        if {[llength $idx] > 0} {
            set line [.left.tables get [lindex $idx 0]]
            set name [string trim $line "• \t"]
            if {$name ne ""} {
                editor_goto_table $name
            }
        }
    }

    grid .left.t1    -row 0 -column 0 -columnspan 2 -sticky ew -padx 8 -pady {8 0}
    grid .left.fname -row 1 -column 0 -columnspan 2 -sticky ew -padx 8 -pady {0 4}
    grid .left.sep   -row 2 -column 0 -columnspan 2 -sticky ew
    grid .left.t2    -row 3 -column 0 -columnspan 2 -sticky ew -padx 8 -pady {6 0}
    grid .left.hd    -row 4 -column 0 -columnspan 2 -sticky ew -padx 8
    grid .left.mr    -row 5 -column 0 -columnspan 2 -sticky ew -padx 8
    grid .left.sep2  -row 6 -column 0 -columnspan 2 -sticky ew -pady 4
    grid .left.t3    -row 7 -column 0 -columnspan 2 -sticky ew -padx 8 -pady {0 2}
    grid .left.tables -row 8 -column 0 -sticky nsew -padx {8 0}
    grid .left.sb     -row 8 -column 1 -sticky ns
    grid columnconfigure .left 0 -weight 1
    grid rowconfigure    .left 8 -weight 1

    # Right panel — notebook with Générer and Éditer tabs
    frame .right

    ttk::notebook .right.nb
    frame .right.nb.gen
    .right.nb add .right.nb.gen -text "Générer"
    pack .right.nb -fill both -expand 1

    text .right.nb.gen.out \
        -wrap word \
        -font {Georgia 12} \
        -state disabled \
        -relief flat \
        -bd 0 \
        -yscrollcommand {.right.nb.gen.sb set} \
        -padx 16 -pady 12
    scrollbar .right.nb.gen.sb -command {.right.nb.gen.out yview}
    pack .right.nb.gen.sb  -side right -fill y
    pack .right.nb.gen.out -fill both  -expand 1

    # Editor tab created by editor_init
    editor_init .right.nb

    .pw add .left  -minsize 180
    .pw add .right -minsize 300

    # ---- Status bar ----
    frame .st -relief flat -bd 0
    pack .st -fill x -side bottom
    frame .st.line -height 1
    pack .st.line -fill x
    label .st.msg -textvariable ::status_msg \
        -anchor w -font {TkDefaultFont 9}
    pack .st.msg -fill x -padx 8 -pady 2

    # ---- Key bindings ----
    bind . <F5>        cmd_generate
    bind . <Control-o> cmd_open

    # ---- Init ----
    set ::ui_fname   "(no file)"
    set ::ui_header  ""
    set ::ui_maxreps ""

    apply_theme $::current_theme

    # Auto-load demo.ipt if present (in project root, not src/)
    set demo [file join $::script_dir demo.ipt]
    if {[file exists $demo]} {
        after 100 [list cmd_load_file $demo]
    }
}

# ============================================================
# HTML → text widget parser
# ============================================================
proc html_current_tag {base active_var} {
    upvar $active_var active
    if {$active(h1)}   { return th1 }
    if {$active(h2)}   { return th2 }
    if {$active(h3)}   { return th3 }
    if {$active(code)} { return tcode }
    if {$active(b) && $active(i)} { return tbold_italic }
    if {$active(b)}    { return tbold }
    if {$active(i)}    { return titalic }
    if {$active(u)}    { return tunderline }
    return $base
}

proc html_insert {w html base_tag} {
    array set active {b 0 i 0 u 0 h1 0 h2 0 h3 0 code 0}
    set pos 0
    set len [string length $html]
    while {$pos < $len} {
        set lt [string first "<" $html $pos]
        if {$lt < 0} {
            set val [string range $html $pos end]
            set val [string map {&amp; & &lt; < &gt; > &quot; \" &apos; ' &nbsp; { }} $val]
            $w insert end $val [html_current_tag $base_tag active]
            break
        }
        if {$lt > $pos} {
            set val [string range $html $pos [expr {$lt-1}]]
            set val [string map {&amp; & &lt; < &gt; > &quot; \" &apos; ' &nbsp; { }} $val]
            $w insert end $val [html_current_tag $base_tag active]
        }
        set gt [string first ">" $html $lt]
        if {$gt < 0} {
            $w insert end [string range $html $lt end] [html_current_tag $base_tag active]
            break
        }
        set tag_name [string tolower [lindex [split [string trim [string range $html [expr {$lt+1}] [expr {$gt-1}]]]] 0]]
        switch -- $tag_name {
            b - strong          { set active(b)  1 }
            /b - /strong        { set active(b)  0 }
            i - em              { set active(i)  1 }
            /i - /em            { set active(i)  0 }
            u                   { set active(u)  1 }
            /u                  { set active(u)  0 }
            h1                  { set active(h1) 1 }
            /h1                 { set active(h1) 0; $w insert end "\n" th1 }
            h2                  { set active(h2) 1 }
            /h2                 { set active(h2) 0; $w insert end "\n" th2 }
            h3                  { set active(h3) 1 }
            /h3                 { set active(h3) 0; $w insert end "\n" th3 }
            code - tt           { set active(code) 1 }
            /code - /tt         { set active(code) 0 }
            br - {br/} - {br /} { $w insert end "\n" $base_tag }
            p                   { $w insert end "\n" $base_tag }
            /p                  { $w insert end "\n" $base_tag }
            hr                  { $w insert end "─────────────────────────────────\n" tsep }
            default             {}
        }
        set pos [expr {$gt+1}]
    }
}

# ============================================================
# COMMANDS
# ============================================================
proc cmd_open {} {
    set f [tk_getOpenFile \
        -title "Open a Sparkwyrd generator" \
        -filetypes {
            {"Sparkwyrd generators" {.ipt}}
            {"All files"            {*}}
        } \
        -initialdir $::script_dir]
    if {$f ne ""} { cmd_load_file $f }
}

proc cmd_load_file {path} {
    set ::status_msg "Loading [file tail $path]..."
    update idletasks

    if {[catch {set ::current_parsed [parse_ipt $path]} err]} {
        set ::status_msg "Error: $err"
        tk_messageBox -type ok -icon error \
            -title "Load error" \
            -message "Cannot read file:\n$err"
        return
    }

    set ::current_file $path
    set h     [dict get $::current_parsed header]
    set order [dict get $::current_parsed order]

    set hd_clean [regsub -all {<[^>]+>} [dict get $h Header] ""]
    set mr [dict get $h MaxReps]

    set ::ui_fname   [file tail $path]
    set ::ui_header  $hd_clean
    set ::ui_maxreps [expr {$mr > 0 ? "MaxReps: $mr" : ""}]

    if {$mr > 0 && $::reps_count > $mr} { set ::reps_count $mr }

    .left.tables delete 0 end
    foreach t $order {
        .left.tables insert end "• $t"
    }

    set n [llength $order]
    set suffix [expr {$n > 1 ? "s" : ""}]
    set ::status_msg "Loaded: [file tail $path] — $n table${suffix}"

    # Load file into editor
    if {$::current_file ne ""} { editor_load $::current_file }

    cmd_generate
}

proc cmd_generate {} {
    if {$::current_parsed eq {}} {
        set ::status_msg "No file loaded — use Open"
        return
    }

    set h  [dict get $::current_parsed header]
    set mr [dict get $h MaxReps]
    set n  $::reps_count
    if {$mr > 0 && $n > $mr} { set n $mr }

    .right.nb.gen.out configure -state normal
    .right.nb.gen.out delete 1.0 end

    set hd_raw [dict get $h Header]
    if {$hd_raw ne ""} {
        html_insert .right.nb.gen.out $hd_raw ttitle
        .right.nb.gen.out insert end "\n─────────────────────────────────\n" tsep
    }

    for {set i 1} {$i <= $n} {incr i} {
        if {[catch {set res [ipt_generate $::current_parsed $i]} err]} {
            set res "  Error: $err"
        }
        html_insert .right.nb.gen.out $res tbody
        .right.nb.gen.out insert end "\n" tbody

        if {$i < $n} {
            .right.nb.gen.out insert end "─────────────────────────────────\n" tsep
        }
    }

    set ft [dict get $h Footer]
    if {$ft ne ""} {
        .right.nb.gen.out insert end "─────────────────────────────────\n" tsep
        html_insert .right.nb.gen.out $ft tsep
        .right.nb.gen.out insert end "\n" tsep
    }

    .right.nb.gen.out configure -state disabled
    .right.nb.gen.out see 1.0
    set plural [expr {$n > 1 ? "s" : ""}]
    set ::status_msg "Generated ($n rep${plural}) — [clock format [clock seconds] -format {%H:%M:%S}]"

    # Switch to Générer tab
    .right.nb select .right.nb.gen
}

proc cmd_clear {} {
    .right.nb.gen.out configure -state normal
    .right.nb.gen.out delete 1.0 end
    .right.nb.gen.out configure -state disabled
    set ::status_msg "Output cleared."
}

# ============================================================
# LAUNCH — wrapped in proc so the merged build controls when it runs.
# ============================================================
proc gui_main {} {
    package require Tk
    build_ui
    if {[llength $::argv] > 0 && [file exists [lindex $::argv 0]]} {
        after 150 [list cmd_load_file [lindex $::argv 0]]
    }
}

if {![info exists ::sparkwyrd_combined]} { gui_main }
