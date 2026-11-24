# PLT-10: load a file from the PC (the Doom WAD) into the SDRAM of the DE10-Lite and check
# that it arrived byte-exact. Uses the JTAG to Avalon Master inside sdram_sys (PLT-10):
#     PC --USB-Blaster/JTAG--> jtag master --Avalon--> SDRAM controller --> SDRAM
#
# The board must be running a design that contains sdram_sys: revision sdram_test or top_doom
# (Doom: docs/doom-lab-checklist.md, image doom.bin at offset 0, then the WAD at the default offset).
# In sdram_test, set SW9 = 1 first (LEDR8 on): otherwise a reset or KEY0 starts the smoke
# test, which writes all 64 MB and erases the file.
#
# Usage (from a terminal; system-console is in <quartus>/sopc_builder/bin):
#     system-console -cli --script=wad_load.tcl <file> [offset] [verify|noverify]
#   offset = byte offset inside the SDRAM, multiple of 4, decimal or 0x... (default 0x03000000)
#   e.g.  system-console -cli --script=src/tools/wad_load.tcl doom1.wad 0x03000000
# Or inside the System Console GUI/CLI:
#     source src/tools/wad_load.tcl
#     wad_load doom1.wad 0x03000000
#     wad_verify doom1.wad 0x03000000        ;# only read back and compare
#
# Byte order: byte i of the file goes to SDRAM byte address offset + i (Avalon byte lanes:
# byte address A+k = byteenable[k]). The CPU bridge (PLT-8) swaps the bytes of each word
# because the CPU is big-endian, so for the CPU too the byte at offset + i is file byte i
# (`lb`), and a word read with `lw` is the 4 file bytes in order, most significant first.

namespace eval wad {
    variable SDRAM_SIZE 0x04000000        ;# 64 MB
    variable DEFAULT_OFFSET 0x03000000    ;# top 16 MB (provisional, see contracts.md)
}

# Opens the first JTAG master found and returns its claimed service path
proc wad::open_master {} {
    set paths [get_service_paths master]
    if {[llength $paths] == 0} {
        error "no JTAG master found: is the board connected and programmed with a design\
that contains sdram_sys (e.g. sdram_test)?"
    }
    if {[llength $paths] > 1} {
        puts "Several masters found, using the first one:"
        foreach p $paths { puts "    $p" }
    }
    return [claim_service master [lindex $paths 0] wad_load]
}

proc wad::check_args {file offset} {
    variable SDRAM_SIZE
    if {![file isfile $file]} { error "file not found: $file" }
    set size [file size $file]
    if {$size == 0} { error "file is empty: $file" }
    if {$offset % 4 != 0} { error "offset must be a multiple of 4: [format 0x%08X $offset]" }
    if {$offset < 0 || $offset + $size > $SDRAM_SIZE} {
        error "[format 0x%08X $offset] + $size bytes does not fit in the 64 MB SDRAM"
    }
    return $size
}

proc wad::read_binary {file} {
    set f [open $file rb]
    set data [read $f]
    close $f
    return $data
}

# Reads size bytes back from the SDRAM and compares them with the file
# Returns 1 if equal; prints the first mismatches otherwise
proc wad::verify {m file offset size} {
    set tmp [file join [file dirname [file normalize $file]] ".wad_readback.bin"]
    set t0 [clock milliseconds]
    master_read_to_file $m $tmp $offset $size
    set ms [expr {max(1, [clock milliseconds] - $t0)}]
    puts [format "Read back  %d bytes in %.1f s (%.0f KB/s)" $size [expr {$ms / 1000.0}] \
        [expr {$size / 1.024 / $ms}]]

    set want [read_binary $file]
    set got [read_binary $tmp]
    file delete $tmp
    if {$want eq $got} { return 1 }

    if {[string length $got] != $size} {
        puts "Read back [string length $got] bytes instead of $size"
    }
    set shown 0
    set bad 0
    set n [expr {min([string length $want], [string length $got])}]
    for {set i 0} {$i < $n} {incr i} {
        if {[string index $want $i] ne [string index $got $i]} {
            incr bad
            if {$shown < 8} {
                binary scan [string index $want $i] cu w
                binary scan [string index $got $i] cu g
                puts [format "  byte %d (SDRAM 0x%08X): file 0x%02X, SDRAM 0x%02X" \
                    $i [expr {$offset + $i}] $w $g]
                incr shown
            }
        }
    }
    puts "$bad bad bytes"
    return 0
}

# Writes the file into the SDRAM at offset, then (by default) reads it back and compares
proc wad_load {file {offset ""} {mode verify}} {
    if {$offset eq ""} { set offset $wad::DEFAULT_OFFSET }
    set offset [expr {$offset}]
    set size [wad::check_args $file $offset]
    set m [wad::open_master]
    set ok 1
    try {
        puts [format "Writing %s (%d bytes) to SDRAM 0x%08X - 0x%08X" \
            [file tail $file] $size $offset [expr {$offset + $size - 1}]]
        set t0 [clock milliseconds]
        master_write_from_file $m [file normalize $file] $offset
        set ms [expr {max(1, [clock milliseconds] - $t0)}]
        puts [format "Written    %d bytes in %.1f s (%.0f KB/s)" $size [expr {$ms / 1000.0}] \
            [expr {$size / 1.024 / $ms}]]
        if {$mode ne "noverify"} {
            set ok [wad::verify $m $file $offset $size]
            puts [expr {$ok ? "PASS: the SDRAM holds the file byte-exact" : "FAIL"}]
        }
    } finally {
        close_service master $m
    }
    return $ok
}

# Only reads back and compares (e.g. after a reset, to see that the file is still there)
proc wad_verify {file {offset ""}} {
    if {$offset eq ""} { set offset $wad::DEFAULT_OFFSET }
    set offset [expr {$offset}]
    set size [wad::check_args $file $offset]
    set m [wad::open_master]
    try {
        set ok [wad::verify $m $file $offset $size]
        puts [expr {$ok ? "PASS: the SDRAM holds the file byte-exact" : "FAIL"}]
    } finally {
        close_service master $m
    }
    return $ok
}

# Run from the command line: system-console -cli --script=wad_load.tcl <file> [offset] [mode]
# (System Console scripts have no `exit`: the result is the PASS/FAIL line)
if {[info exists argv] && [llength $argv] > 0} {
    if {[catch {wad_load {*}$argv} err]} { puts "ERROR: $err" }
}
