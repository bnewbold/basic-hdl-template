# Device-specific make targets

.PHONY: scp remote_xdevcfg prog_ssh

zynq_ssh_host ?= zedboard

bitfile_list += build/$(project).bit.bin

scp: build/$(project).bit.bin
	scp build/$(project).bit.bin $(zynq_ssh_host):/mnt

prog_ssh:
	@# Fail if build/$(project).bit.bin not built yet
	@[ -f build/$(project).bit.bin ] || false
	scp build/$(project).bit.bin $(zynq_ssh_host):/mnt
	@echo "Creating /dev/xdevcfg if it doesn't exist already..."
	ssh $(zynq_ssh_host) -- "[ -c /dev/xdevcfg ] || mknod /dev/xdevcfg c 259 0"
	@echo "Loading bitfile into PL..."
	ssh $(zynq_ssh_host) -- "cat /mnt/$(project).bit.bin > /dev/xdevcfg"

build/$(project).bit.bin: build/$(project).bit
	@bash -c "$(xil_env); promgen -b -p bin -data_width 32 -u 0x0 $(project).bit -w -o $(project).bit.bin"
