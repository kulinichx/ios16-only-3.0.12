#include "info.h"
#include "kernel.h"
#include "machine_info.h"
#include "primitives.h"
#include "util.h"
#include <sys/utsname.h>
#include <xpc/xpc.h>
#include <sys/types.h>
#include <sys/sysctl.h>

struct system_info gSystemInfo = { 0 };

void jbinfo_initialize_dynamic_offsets(xpc_object_t xoffsetDict)
{
	SYSTEM_INFO_DESERIALIZE(xoffsetDict);
}

void jbinfo_initialize_boot_constants(void)
{
	gSystemInfo.kernelConstant.base     = kconstant(staticBase) + gSystemInfo.kernelConstant.slide;
	gSystemInfo.kernelConstant.virtBase = kread64(ksymbol(gVirtBase));
	//gSystemInfo.kernelConstant.virtSize = ...;
	gSystemInfo.kernelConstant.physBase = kread64(ksymbol(gPhysBase));
	gSystemInfo.kernelConstant.physSize = kread64(ksymbol(gPhysSize));
	gSystemInfo.kernelConstant.cpuTTEP  = kread64(ksymbol(cpu_ttep));

}

xpc_object_t jbinfo_get_serialized(void)
{
	xpc_object_t systemInfo = xpc_dictionary_create_empty();
	SYSTEM_INFO_SERIALIZE(systemInfo);
	return systemInfo;
}

uint64_t get_vm_real_kernel_page_size(void)
{
	static uint64_t real_kernel_page_size = 0;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		real_kernel_page_size = vm_kernel_page_size;

	});
	return real_kernel_page_size;
}

uint64_t get_vm_real_kernel_page_shift(void)
{
	static uint64_t real_kernel_page_shift = 0;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		real_kernel_page_shift = vm_kernel_page_shift;

	});
	return real_kernel_page_shift;
}

uint64_t get_l1_block_size(void)
{
	switch (vm_real_kernel_page_size) {
		case 0x4000:
		return 0x1000000000;
		default:
		return 0;
	}
}

uint64_t get_l1_block_mask(void)
{
	return get_l1_block_size() - 1;
}

uint64_t get_l1_block_count(void)
{
	switch (vm_real_kernel_page_size) {
		case 0x4000:
		return 8;
		default:
		return 0;
	}
}

uint64_t get_l2_block_size(void)
{
	switch (vm_real_kernel_page_size) {
		case 0x4000:
		return 0x2000000;
		default:
		return 0;
	}
}

uint64_t get_l2_block_mask(void)
{
	return get_l2_block_size() - 1;
}

uint64_t get_l2_block_count(void)
{
	switch (vm_real_kernel_page_size) {
		case 0x4000:
		return 2048;
		default:
		return 0;
	}
}
