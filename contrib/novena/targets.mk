# novena device-specific configuration make targets.
# put variables in settings.mk, not this file.

.PHONY: prog

# This target uploads directly to the FPGA; volatile
prog: build/$(project).bit
	@echo "novena board uploading is not implemented!"
	@false
 
