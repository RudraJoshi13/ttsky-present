# PnR constraints (placement, CTS, routing and all repair steps).
# Start from Tiny Tapeout's own constraints file, unchanged ...
source $::env(SCRIPTS_DIR)/base.sdc

# ... then aim slew repair at 0.5 ns instead of the default 0.75 ns.
# Signoff (STA after routing) still uses base.sdc, so the design is
# still judged against the default 0.75 ns limit.
set_max_transition 0.5 [current_design]

# ... and aim fanout repair at 8 instead of 10. Antenna diodes are added
# after repair and count as loads at signoff, so this leaves room for two.
# Signoff (signoff.sdc) still checks fanout against 10.
set_max_fanout 8 [current_design]
