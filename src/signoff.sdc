# Signoff constraints (STA after routing).
# Tiny Tapeout's own constraints file, unchanged, so the design is judged
# against the default limits (0.75 ns slew, 0.2 pF cap, fanout 10).
# Without this file set as SIGNOFF_SDC_FILE, signoff reuses pnr.sdc (0.5 ns slew).
source $::env(SCRIPTS_DIR)/base.sdc
