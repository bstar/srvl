"""Translate the pinned Lynx console for a resource audit, not a playable port.

The Intel dpram primitive is replaced and three formal integer ranges are made
consistent with their callers for GHDL synthesis. Both RAM ports have the same
clock upstream. Collision behavior still needs validation for a hardware port.
"""
from pathlib import Path
import hashlib
import difflib
import json
import os
import re
import shutil
import subprocess
import sys

source, dest = (Path(arg).resolve() for arg in sys.argv[1:])
dest.mkdir(parents=True, exist_ok=True)
rtl = dest / "rtl"
rtl.mkdir()
files = re.findall(r"-name VHDL_FILE rtl/(\S+)", (source / "files.qip").read_text())
manifest = {}
for name in files:
    data = (source / "rtl" / name).read_bytes()
    manifest[name] = hashlib.sha256(data).hexdigest()
    (rtl / name).write_bytes(data)
shutil.copy(source / "LICENSE", dest / "LICENSE.upstream")
(dest / "source-sha256.json").write_text(json.dumps(manifest, indent=2) + "\n")

# Retain the public dpram port declarations verbatim. dpram_dif is not used by
# LynxTop; excluding it avoids a second unused Intel primitive definition.
original = (rtl / "dpram.vhd").read_text()
declaration = original[:original.index("ARCHITECTURE SYN OF dpram IS")]
declaration = declaration.replace("LIBRARY altera_mf;", "")
declaration = declaration.replace("USE altera_mf.altera_mf_components.all;", "")
(rtl / "dpram.vhd").write_text(declaration + '''
-- Audit-only same-clock RAM adapter. Not a verified replacement for altsyncram.
library ieee;
use ieee.numeric_std.all;
architecture audit of dpram is
  type memory_t is array(0 to 2**addr_width-1) of std_logic_vector(data_width-1 downto 0);
  signal memory : memory_t := (others => (others => '0'));
  attribute no_rw_check : boolean;
  attribute no_rw_check of memory : signal is true;
  attribute ram_style : string;
  attribute ram_style of memory : signal is "block";
  signal raw_a, raw_b : std_logic_vector(data_width-1 downto 0) := (others => '0');
  signal written_a, written_b : std_logic_vector(data_width-1 downto 0) := (others => '0');
  signal bypass_a, bypass_b : std_logic := '0';
begin
  -- Own-port write-through is explicit outside the memory. Mixed-port
  -- read/write collisions are unspecified, as with the upstream primitive.
  q_a <= written_a when bypass_a = '1' else raw_a;
  q_b <= written_b when bypass_b = '1' else raw_b;
  process(clock_a)
  begin
    if rising_edge(clock_a) then
      if clken_a = '1' then
        raw_a <= memory(to_integer(unsigned(address_a)));
        bypass_a <= wren_a;
        written_a <= data_a;
        if wren_a = '1' then
          memory(to_integer(unsigned(address_a))) <= data_a;
        end if;
      end if;
      if clken_b = '1' then
        raw_b <= memory(to_integer(unsigned(address_b)));
        bypass_b <= wren_b;
        written_b <= data_b;
        if wren_b = '1' then
          memory(to_integer(unsigned(address_b))) <= data_b;
        end if;
      end if;
    end if;
  end process;
end architecture;
''')

# Quartus accepts these mismatched formal integer subtypes; GHDL synthesis does
# not. Narrow formals to the ranges already guaranteed by their only callers.
for name, replacements in {
    "overlay.vhd": [("i_pixel_out_x          : in  integer range 0 to 2047;",
                     "i_pixel_out_x          : in  integer range 0 to 159;"),
                    ("i_pixel_out_y          : in  integer range 0 to 1023;",
                     "i_pixel_out_y          : in  integer range 0 to 101;")],
    "statemanager.vhd": [("savestate_number    : in    integer;",
                          "savestate_number    : in    integer range 0 to 3;")],
}.items():
    text = (rtl / name).read_text()
    for before, after in replacements:
        assert text.count(before) == 1, f"Upstream changed: {name}"
        text = text.replace(before, after)
    (rtl / name).write_text(text)

diff = []
for name in files:
    diff.extend(difflib.unified_diff((source / "rtl" / name).read_text().splitlines(True),
                                   (rtl / name).read_text().splitlines(True),
                                   fromfile="upstream/" + name, tofile="audit/" + name))
(dest / "audit-adaptations.patch").write_text("".join(diff))

top = (rtl / "lynxTop.vhd").read_text()
port_text = top.split("   port", 1)[1].split("end entity;", 1)[0]
port_text = port_text[port_text.index("(") + 1:port_text.rindex(");")]
port_text = re.sub(r"--[^\n]*", "", port_text)
ports = {}
for item in port_text.split(";"):
    if item.strip():
        name, decl = item.strip().split(":", 1)
        ports[name.strip()] = decl.strip()

constants = {
    "pause_in": "'0'", "fastforward": "'0'", "turbo": "'0'",
    "speedselect": '"00"', "fpsoverlay_on": "'0'",
    "increaseSSHeaderCount": "'0'", "save_state": "'0'", "load_state": "'0'",
    "savestate_number": "0", "state_loaded": "open",
    "SAVE_out_Din": "open", "SAVE_out_Dout": "(others => '0')",
    "SAVE_out_Adr": "open", "SAVE_out_rnw": "open", "SAVE_out_ena": "open",
    "SAVE_out_be": "open", "SAVE_out_done": "'1'",
    "rewind_on": "'0'", "rewind_active": "'0'",
    "cheat_clear": "'0'", "cheats_enabled": "'0'", "cheat_on": "'0'",
    "cheat_in": "(others => '0')", "cheats_active": "open",
}
assert not (constants.keys() - ports.keys()), "Upstream interface changed"
exposed = [f"    {name} : {decl}" for name, decl in ports.items() if name not in constants]
mapping = [f"    {name} => {constants.get(name, name)}" for name in ports]
wrapper = '''library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity lynx_audit is
  port (
''' + ";\n".join(exposed) + '''
  );
end entity;
architecture audit of lynx_audit is
begin
  console : entity work.LynxTop
  generic map (is_simu => '0')
  port map (
''' + ",\n".join(mapping) + '''
  );
end architecture;
'''
(rtl / "lynx_audit.vhd").write_text(wrapper)
(dest / "audit-configuration.json").write_text(json.dumps({
    "top": "lynx_audit", "constant_ports": constants,
    "scope": "console only; no display buffers, SDRAM controller, loader, HDMI, board IO or PLL",
    "ram_adapter": "audit-only inferred same-clock dpram; collision semantics not verified",
}, indent=2) + "\n")
os.chdir(rtl)
subprocess.run(["ghdl", "-a", "--std=08", "-fsynopsys", *files, "lynx_audit.vhd"], check=True)
with (dest / "lynx.v").open("w") as output:
    subprocess.run(["ghdl", "--synth", "--std=08", "-fsynopsys", "--out=verilog", "lynx_audit"],
                   stdout=output, check=True)

# GHDL expands initialized RAM into tens of thousands of individual assignments.
# Keep its output and also emit equivalent readmemh initializers for synthesis.
# Explicitly verify complete, unique address coverage before compacting a block.
initializers = []
def compact_memory(match):
    assignments = re.findall(r"    (\w+)\[(\d+)\] = (\d+)'b([01]+);\n", match[1])
    names = {item[0] for item in assignments}
    widths = {int(item[2]) for item in assignments}
    assert len(names) == len(widths) == 1
    values = {int(item[1]): int(item[3], 2) for item in assignments}
    assert len(values) == len(assignments)
    assert set(values) == set(range(len(values)))
    width = widths.pop()
    name = f"memory-init-{len(initializers)}.hex"
    (dest / name).write_text("".join(f"{values[address]:0{(width+3)//4}x}\n" for address in range(len(values))))
    initializers.append({"file": name, "words": len(values), "width": width})
    return f'  initial $readmemh("{dest / name}", {names.pop()});\n'

translated = (dest / "lynx.v").read_text()
compact = re.sub(r"  initial begin\n((?:    \w+\[\d+\] = \d+'b[01]+;\n)+)    end\n", compact_memory, translated)
assert any(item["words"] == 65536 for item in initializers), "RAM initializer layout changed"
(dest / "lynx-compact.v").write_text(compact)
(dest / "memory-initializers.json").write_text(json.dumps(initializers, indent=2) + "\n")
for database in rtl.glob("*.cf"):
    database.unlink()
