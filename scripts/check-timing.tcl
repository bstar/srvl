# Run with quartus_sta -t scripts/check-timing.tcl SRVL after fitting.
package require ::quartus::project
package require ::quartus::sta
project_open [lindex $quartus(args) 0]
create_timing_netlist
read_sdc
update_timing_netlist
report_clocks -file prototype-clocks.rpt
set found_demo_clock 0
foreach_in_collection clock [get_clocks *] {
    set period [get_clock_info -period $clock]
    if {abs($period - (1000.0 / 50.4)) < 0.01} {
        set found_demo_clock 1
    }
}
if {!$found_demo_clock} {
    post_message -type error "No 50.4 MHz clock found in fitted timing netlist"
    exit 1
}
foreach check {setup hold} {
    report_timing -$check -npaths 5 -detail full_path -file prototype-$check.rpt
    set paths [get_timing_paths -$check -npaths 1]
    if {[get_collection_size $paths] == 0} {
        post_message -type error "No $check timing paths found"
        exit 1
    }
    foreach_in_collection path $paths {
        set slack [get_path_info -slack $path]
        post_message "Worst $check slack: $slack ns"
        if {$slack < 0} {
            set report [open prototype-$check.rpt r]
            puts [read $report]
            close $report
            post_message -type error "Fitted design fails $check timing"
            exit 1
        }
    }
}
delete_timing_netlist
project_close
