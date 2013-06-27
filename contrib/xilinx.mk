# This file oritinally came from excamera's build example.
#
# The top level module should define the variables below then include
# this file.  The files listed should be in the same directory as the
# Makefile.  
#
# TODO: update these listings
#
#   variable	description
#   ----------  -------------
#   project	project name (top level module should match this name)
#   top_module  top level module of the project
#   libdir	path to library directory
#   libs	library modules used
#   vfiles	all local .v files
#   xilinx_cores  all local .xco files
#   vendor      vendor of FPGA (xilinx, altera, etc.)
#   family      FPGA device family (spartan3e) 
#   part        FPGA part name (xc4vfx12-10-sf363)
#   flashsize   size of flash for mcs file (16384)
#   optfile     (optional) xst extra opttions file to put in .scr
#   map_opts    (optional) options to give to map
#   par_opts    (optional) options to give to par
#   intstyle    (optional) intstyle option to all tools
#
#   files 		description
#   ----------  	------------
#   $(project).ucf	ucf file
#
# Library modules should have a modules.mk in their root directory,
# namely $(libdir)/<libname>/module.mk, that simply adds to the vfiles
# and xilinx_cores variable.
#
# all the .xco files listed in xilinx_cores will be generated with core, with
# the resulting .v and .ngc files placed back in the same directory as
# the .xco file.
#
# TODO: .xco files are device dependant, should use a template based system
#
# NOTE: DO NOT edit this file to change settings; instead edit Makefile

synth_effort ?= high
coregen_work_dir ?= ./coregen-tmp
map_opts ?= -timing -ol $(synth_effort) -detail -pr b -register_duplication -w
par_opts ?= -ol $(synth_effort) -rl $(synth_effort)
hostbits = 64
iseenv= /opt/Xilinx/14.3/ISE_DS
iseenvfile?= $(iseenv)/settings$(hostbits).sh
xil_env ?= mkdir -p build/; cd ./build; source $(iseenvfile) > /dev/null
sim_env ?= cd ./tb; source $(iseenvfile) > /dev/null
flashsize ?= 8192
mcs_datawidth ?= 16

PWD := $(shell pwd)
intstyle ?= -intstyle xflow
colorize ?= 2>&1 | python $(PWD)/contrib/colorize.py red ERROR: yellow WARNING: green \"Number of error messages: 0\" green \"Number of error messages:\t0\" green \"Number of errors:     0\"

multithreading ?= -mt 4

libmks = $(patsubst %,$(libdir)/%/module.mk,$(libs)) 
mkfiles = Makefile $(libmks) contrib/xilinx.mk
include $(libmks)

# default is a single file
tbfiles ?= ./tb/tb.v

corengcs = $(foreach core,$(xilinx_cores),$(core:.xco=.ngc))
local_corengcs = $(foreach ngc,$(corengcs),$(notdir $(ngc)))
vfiles += $(foreach core,$(xilinx_cores),$(core:.xco=.v))
tbmods = $(foreach tbm,$(tbfiles),unenclib.`basename $(tbm) .v`)

.PHONY: default xilinx_cores clean twr_map twr_par ise isim simulate coregen impact ldimpact lint planahead partial_fpga_editor final_fpga_editor partial_timing final_timing
default: build/$(project).bit build/$(project).mcs
xilinx_cores: $(corengcs)
twr_map: build/$(project)_post_map.twr
twr_par: build/$(project)_post_par.twr

define cp_template
$(2): $(1)
	cp $(1) $(2)
endef
$(foreach ngc,$(corengcs),$(eval $(call cp_template,$(ngc),$(notdir $(ngc)))))

$(coregen_work_dir)/$(project).cgp: contrib/template.cgp
	@if [ -d $(coregen_work_dir) ]; then \
		rm -rf $(coregen_work_dir)/*; \
	else \
		mkdir -p $(coregen_work_dir); \
	fi
	@cp contrib/template.cgp $@
	@echo "SET designentry = Verilog " >> $@
	@echo "SET device = $(device)" >> $@
	@echo "SET devicefamily = $(family)" >> $@
	@echo "SET package = $(device_package)" >> $@
	@echo "SET speedgrade = $(speedgrade)" >> $@
	@echo "SET workingdirectory = ./tmp/" >> $@

%.ngc %.v: %.xco $(coregen_work_dir)/$(project).cgp
	@echo "=== rebuilding $@"
	@bash -c "$(xil_env); cd ../$(coregen_work_dir); coregen -b ../$< -p $(project).cgp;"
	@xcodir=`dirname $<`; \
	basename=`basename $< .xco`; \
	echo $(coregen_work_dir)/$$basename.v; \
	if [ ! -r $(coregen_work_dir)/$$basename.ngc ]; then \
		echo "'$@' wasn't created."; \
		exit 1; \
	else \
		cp $(coregen_work_dir)/$$basename.v $(coregen_work_dir)/$$basename.ngc $$xcodir; \
	fi

date = $(shell date +%F-%H-%M)

programming_files: build/$(project).bit build/$(project).mcs
	@mkdir -p $@/$(date)
	@mkdir -p $@/latest
	@for x in .bit .mcs .cfi _bd.bmm; do cp $(project)$$x $@/$(date)/$(project)$$x; cp $(project)$$x $@/latest/$(project)$$x; done
	@bash -c "$(xil_env); xst -help | head -1 | sed 's/^/#/' | cat - build/$(project).scr > $@/$(date)/$(project).scr"

build/$(project).mcs: build/$(project).bit
	@bash -c "$(xil_env); promgen -w -data_width $(mcs_datawidth) -s $(flashsize) -p mcs -o $(project).mcs -u 0 $(project).bit"

build/$(project).bit: build/$(project)_par.ncd build/$(project)_post_par.twr
	@bash -c "$(xil_env); \
	bitgen $(intstyle) -g Binary:yes -g DriveDone:yes -g StartupClk:Cclk -w $(project)_par.ncd $(project).bit"


build/$(project)_par.ncd: build/$(project).ncd build/$(project)_post_map.twr
	@bash -c "$(xil_env); \
	if par $(intstyle) $(par_opts) -w $(project).ncd $(project)_par.ncd $(multithreading) $(colorize); then \
		:; \
	else \
		echo "Oh noes! Check timing analysis? build/$(project)_post_map.twr"; \
	fi "

build/$(project).ncd: build/$(project).ngd
	@if [ -r $(project)_par.ncd ]; then \
		cp $(project)_par.ncd smartguide.ncd; \
		smartguide="-smartguide smartguide.ncd"; \
	else \
		smartguide=""; \
	fi; \
	bash -c "$(xil_env); \
	map $(intstyle) $(map_opts) $$smartguide $(project).ngd $(multithreading) $(colorize)"

build/$(project).ngd: build/$(project).ngc $(project).ucf $(project).bmm
	@bash -c "$(xil_env); \
	ngdbuild $(intstyle) $(project).ngc -bm ../$(project).bmm -sd ../cores -uc ../$(project).ucf -aul $(colorize)"

build/$(project).ngc: $(vfiles) $(local_corengcs) build/$(project).scr build/$(project).prj
	@bash -c "$(xil_env); xst $(intstyle) -ifn $(project).scr $(colorize)"

build/$(project).prj: $(vfiles)
	@for src in $(vfiles); do echo "verilog work ../$$src" >> $(project).tmpprj; done
	@sort -u $(project).tmpprj > $@
	@rm -f $(project).tmpprj

optfile += $(wildcard $(project).opt)
top_module ?= $(project)
build/$(project).scr: $(optfile) $(mkfiles) ./$(project).opt
	mkdir -p build
	@echo "run" > $@
	@echo "-p $(part)" >> $@
	@echo "-top $(top_module)" >> $@
	@echo "-ifn $(project).prj" >> $@
	@echo "-ofn $(project).ngc" >> $@
	@cat $(optfile) >> $@
	cp $@ build/$(project).xst

build/$(project)_post_map.twr: build/$(project).ncd
	@bash -c "$(xil_env); trce -u 10 -e 20 -l 10 $(project) -o $(project)_post_map.twr $(colorize)"
	@echo "Read $@ for timing analysis details"

build/$(project)_post_par.twr: build/$(project)_par.ncd
	@bash -c "$(xil_env); trce -u 10 -e 20 -l 10 $(project)_par -o $(project)_post_par.twr $(colorize)"
	@echo "See $@ for timing analysis details"

tb/simulate_isim.prj: $(tbfiles) $(vfiles) $(mkfiles)
	@rm -f $@
	@for f in $(vfiles); do \
		echo "verilog unenclib ../$$f" >> $@; \
	done
	@for f in $(tbfiles); do \
		echo "verilog unenclib ../$$f" >> $@; \
	done
	@echo "verilog unenclib $(iseenv)/ISE/verilog/src/glbl.v" >> $@

tb/isim: tb/simulate_isim.prj $(tbfiles) $(vfiles) $(mkfiles)
	@bash -c "$(sim_env); cd ../tb/; vlogcomp -prj simulate_isim.prj $(colorize)"

tb/simulate_isim: tb/isim $(tbfiles) $(vfiles) $(mkfiles)
	@bash -c "$(sim_env); cd ../tb/; fuse -lib unisims_ver -lib secureip -lib xilinxcorelib_ver -lib unimacro_ver -lib iplib=./iplib -lib unenclib -o simulate_isim $(tbmods) unenclib.glbl $(colorize)"

simulate: tb/simulate_isim

isim_cli: simulate
	@bash -c "$(sim_env); cd ../tb/; ./simulate_isim"

isim: simulate
	@bash -c "$(sim_env); cd ../tb/; ./simulate_isim -gui -view signals.wcfg &"

coregen: $(coregen_work_dir)/$(project).cgp
	@bash -c "$(xil_env); cd ../$(coregen_work_dir); coregen -p $(project).cgp &"

impact:
	@bash -c "$(xil_env); cd ../build; impact &"

ldimpact:
	@bash -c "$(xil_env); cd ../build; LD_PRELOAD=/usr/local/lib/libusb-driver.so impact &"

ise:
	@echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	@echo "! WARNING: you might need to update ISE's project settings !"
	@echo "!          (see README)                                    !"
	@echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	@mkdir -p build
	@bash -c "$(xil_env); cd ..; XIL_MAP_LOCWARN=0 ise $(project).xise &"

planahead:
	@bash -c "$(xil_env); cd ..; planAhead &"

# TODO: DISPLAY = `echo $DISPLAY |sed s/'\.0'//`
partial_fpga_editor: build/$(project).ncd
	@echo "Starting fpga_editor in the background (can take a minute or two)..."
	@bash -c "$(xil_env); DISPLAY=:0 fpga_editor $(project).ncd &"

# TODO: DISPLAY = `echo $DISPLAY |sed s/'\.0'//`
final_fpga_editor: build/$(project)_par.ncd
	@echo "Starting fpga_editor in the background (can take a minute or two)..."
	@bash -c "$(xil_env); DISPLAY=:0 fpga_editor $(project)_par.ncd &"

partial_timing: build/$(project)_post_map.twr
	@bash -c "$(xil_env); timingan -ucf ../$(project).ucf $(project)_par.ncd $(project).pcf $(project)_post_map.twx &"

final_timing: build/$(project)_post_par.twr
	@bash -c "$(xil_env); timingan -ucf ../$(project).ucf $(project)_par.ncd $(project).pcf $(project)_post_par.twx &"

lint:
	verilator --lint-only -Wall -I./hdl -I./cores -Wall $(top_module)

clean: clean_synth clean_sim
	rm -rf iseconfig

clean_sim::
	rm -f tb/simulate_isim tb/*.log tb/*.cmd tb/*.xmsgs tb/*.prj
	rm -rf tb/isim

clean_synth::
	rm -rf build
	rm -rf coregen-tmp

