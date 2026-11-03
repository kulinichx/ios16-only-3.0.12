#include "info.h"
#include "kernel.h"
#include "machine_info.h"
#include "util.h"
#include <stdio.h>
#include <string.h>
#include <sys/utsname.h>
#include <sys/sysctl.h>

struct xnu_version {
	uint64_t major;
	uint64_t minor;
	uint64_t patch;
};

static int xnu_version_compare(struct xnu_version left, struct xnu_version right)
{
	if (left.major != right.major) return left.major > right.major ? 1 : -1;
	if (left.minor != right.minor) return left.minor > right.minor ? 1 : -1;
	if (left.patch != right.patch) return left.patch > right.patch ? 1 : -1;
	return 0;
}

void jbinfo_initialize_hardcoded_offsets(void)
{
	struct utsname name;
	uname(&name);
	char *darwinVersion = name.release;
	struct xnu_version xnuVersion = { 0 };
	if (sscanf(strstr(name.version, "xnu-"), "xnu-%llu.%llu.%llu~%*s", &xnuVersion.major, &xnuVersion.minor, &xnuVersion.patch) != 3) {
		sscanf(strstr(name.version, "xnu-"), "xnu-%llu.%llu.%*s", &xnuVersion.major, &xnuVersion.minor);
	}

	bool isArm64e = host_is_arm64e();
	cpu_subtype_t cpuFamily = 0;
	size_t cpuFamilySize = sizeof(cpuFamily);
	sysctlbyname("hw.cpufamily", &cpuFamily, &cpuFamilySize, NULL, 0);

	bool hasJitbox = (cpuFamily == CPUFAMILY_ARM_BLIZZARD_AVALANCHE ||
					  cpuFamily == CPUFAMILY_ARM_EVEREST_SAWTOOTH);
	uint32_t taskJitboxAdjust = hasJitbox ? 0x18 : 0;
	uint32_t pmapEl2Adjust = kconstant(kernel_el) == 2 ? 8 : 0;
	uint32_t pmapA11Adjust = cpuFamily == CPUFAMILY_ARM_MONSOON_MISTRAL ? 2 : 0;

	gSystemInfo.kernelConstant.PVH_TYPE_MASK = 0x3;
	gSystemInfo.kernelConstant.PVH_HIGH_FLAGS = 0x7F40000000000000;
	gSystemInfo.kernelConstant.VM_PAGE_PACKED_PTR_SHIFT = 6;
	gSystemInfo.kernelConstant.VM_PAGE_PACKED_PTR_BASE = 0xFFFFFFE000000000;
	gSystemInfo.kernelConstant.TFRO_PLATFORM = 0x400;
	gSystemInfo.kernelConstant.TFRO_HARDENED = 0;
	gSystemInfo.kernelConstant.smrBase = 3;

	gSystemInfo.kernelStruct.IOSurface.memoryDescriptor = 0x38;
	gSystemInfo.kernelStruct.IOMachPort.object = 0;

	gSystemInfo.kernelStruct.proc.list_next = 0;
	gSystemInfo.kernelStruct.proc.list_prev = 0x8;
	gSystemInfo.kernelStruct.proc.task = 0;
	gSystemInfo.kernelStruct.proc.pptr = 0x10;
	gSystemInfo.kernelStruct.proc.proc_ro = 0x18;
	gSystemInfo.kernelStruct.proc.svuid = 0x3C;
	gSystemInfo.kernelStruct.proc.svgid = 0x40;
	gSystemInfo.kernelStruct.proc.pid = 0x60;
	gSystemInfo.kernelStruct.proc.fd = 0xD0;
	gSystemInfo.kernelStruct.proc.flag = 0x25C;
	gSystemInfo.kernelStruct.proc.textvp = 0x350;
	gSystemInfo.kernelStruct.proc.ucred = 0;
	gSystemInfo.kernelStruct.proc.csflags = 0;

	gSystemInfo.kernelStruct.proc_ro.exists = true;
	gSystemInfo.kernelStruct.proc_ro.csflags = 0x1C;
	gSystemInfo.kernelStruct.proc_ro.ucred = 0x20;
	gSystemInfo.kernelStruct.proc_ro.task_tokens = 0x40;
	gSystemInfo.kernelStruct.proc_ro.syscall_filter_mask = 0x28;
	gSystemInfo.kernelStruct.proc_ro.mach_trap_filter_mask = 0x68;
	gSystemInfo.kernelStruct.proc_ro.mach_kobj_filter_mask = 0x70;
	gSystemInfo.kernelStruct.task_token_ro_data.audit_token = 0x8;

	gSystemInfo.kernelStruct.filedesc.ofiles_start = 0x28;
	gSystemInfo.kernelStruct.fileproc.glob = 0x10;
	gSystemInfo.kernelStruct.fileglob.data = 0x38;
	gSystemInfo.kernelStruct.vnode.un = 0x78;
	gSystemInfo.kernelStruct.ubc_info.cs_blobs = 0x50;
	gSystemInfo.kernelStruct.cs_blob.next = 0;
	gSystemInfo.kernelStruct.cs_blob.cpu_type = 0x18;
	gSystemInfo.kernelStruct.cs_blob.cpu_subtype = 0x1C;
	gSystemInfo.kernelStruct.cs_blob.base_offset = 0x28;

	gSystemInfo.kernelStruct.task.map = 0x28;
	gSystemInfo.kernelStruct.task.threads = 0x60;
	if (isArm64e) {
		gSystemInfo.kernelStruct.task.task_can_transfer_memory_ownership = 0x548 + taskJitboxAdjust;
		gSystemInfo.kernelStruct.task.flags = 0x3B8 + taskJitboxAdjust;
	} else {
		gSystemInfo.kernelStruct.task.task_can_transfer_memory_ownership = 0x528;
		gSystemInfo.kernelStruct.task.flags = 0x3A0;
	}

	gSystemInfo.kernelStruct.ipc_space.table = 0x20;
	gSystemInfo.kernelStruct.ipc_space.table_uses_smr = false;
	gSystemInfo.kernelStruct.ipc_entry.object = 0;
	gSystemInfo.kernelStruct.ipc_entry.struct_size = 0x18;
	gSystemInfo.kernelStruct.ipc_port.kobject = 0x48;

	gSystemInfo.kernelStruct.vm_map.hdr = 0x10;
	gSystemInfo.kernelStruct.vm_map.flags = 0xB4;
	gSystemInfo.kernelStruct.vm_map_header.last = 0;
	gSystemInfo.kernelStruct.vm_map_header.first = 0x8;
	gSystemInfo.kernelStruct.vm_map_header.min_offset = 0x10;
	gSystemInfo.kernelStruct.vm_map_header.max_offset = 0x18;
	gSystemInfo.kernelStruct.vm_map_header.nentries = 0x20;
	gSystemInfo.kernelStruct.vm_map_entry.prev = 0;
	gSystemInfo.kernelStruct.vm_map_entry.next = 0x8;
	gSystemInfo.kernelStruct.vm_map_entry.start = 0x10;
	gSystemInfo.kernelStruct.vm_map_entry.end = 0x18;
	gSystemInfo.kernelStruct.vm_map_entry.flags = 0x48;
	gSystemInfo.kernelStruct.vm_map_entry.flags_prot = 7;
	gSystemInfo.kernelStruct.vm_map_entry.flags_maxprot = 11;
	gSystemInfo.kernelStruct.vm_map_entry.flags_xnu_user_debug = 28;

	gSystemInfo.kernelStruct.pmap.tte = 0;
	gSystemInfo.kernelStruct.pmap.ttep = 0x8;
	if (isArm64e) {
		gSystemInfo.kernelStruct.pmap.pmap_cs_main = 0x90;
		gSystemInfo.kernelStruct.pmap.sw_asid = 0xB6 + pmapEl2Adjust;
		gSystemInfo.kernelStruct.pmap.wx_allowed = 0xBA + pmapEl2Adjust;
		gSystemInfo.kernelStruct.pmap.type = 0xC0 + pmapEl2Adjust;
		gSystemInfo.kernelStruct.pmap_cs_region.pmap_cs_region_next = 0;
		gSystemInfo.kernelStruct.pmap_cs_region.cd_entry = 0x28;
		gSystemInfo.kernelStruct.pmap_cs_code_directory.pmap_cs_code_directory_next = 0;
		gSystemInfo.kernelStruct.pmap_cs_code_directory.main_binary = 0x190;
		gSystemInfo.kernelStruct.pmap_cs_code_directory.trust = 0x1DC;
	} else {
		gSystemInfo.kernelStruct.pmap.sw_asid = 0x8E;
		gSystemInfo.kernelStruct.pmap.wx_allowed = 0;
		gSystemInfo.kernelStruct.pmap.type = 0x94 + pmapA11Adjust;
	}
	gSystemInfo.kernelStruct.pt_desc.pmap = 0x10;
	gSystemInfo.kernelStruct.pt_desc.va = 0x18;
	gSystemInfo.kernelStruct.pt_desc.ptd_info = koffsetof(pt_desc, va) + kconstant(PT_INDEX_MAX) * sizeof(uint64_t);

	gSystemInfo.kernelStruct.ucred.rw = 0;
	gSystemInfo.kernelStruct.ucred.ref = 0x10;
	gSystemInfo.kernelStruct.ucred.uid = 0x18;
	gSystemInfo.kernelStruct.ucred.ruid = 0x1C;
	gSystemInfo.kernelStruct.ucred.svuid = 0x20;
	gSystemInfo.kernelStruct.ucred.groups = 0x28;
	gSystemInfo.kernelStruct.ucred.rgid = 0x68;
	gSystemInfo.kernelStruct.ucred.svgid = 0x6C;
	gSystemInfo.kernelStruct.ucred.label = 0x78;
	gSystemInfo.kernelStruct.ucred_rw.exists = true;
	gSystemInfo.kernelStruct.ucred_rw.weak_ref = 0;

	gSystemInfo.kernelStruct.trustcache.nextptr = 0;
	gSystemInfo.kernelStruct.trustcache.prevptr = 0x8;
	gSystemInfo.kernelStruct.trustcache.type = 0x10;
	gSystemInfo.kernelStruct.trustcache.size = 0x18;
	gSystemInfo.kernelStruct.trustcache.fileptr = 0x20;
	gSystemInfo.kernelStruct.trustcache.struct_size = 0x28;
	gSystemInfo.kernelStruct.inpcb.list_next = 0x20;
	gSystemInfo.kernelStruct.inpcb.list_prev = 0x28;
	gSystemInfo.kernelStruct.inpcb.pcbinfo = 0x38;
	gSystemInfo.kernelStruct.inpcb.socket = 0x40;
	gSystemInfo.kernelStruct.inpcb.icmp6filt = 0x150;
	gSystemInfo.kernelStruct.inpcb.chksum = 0x158;
	gSystemInfo.kernelStruct.inpcbinfo.ipi_zone = 0x68;
	gSystemInfo.kernelStruct.kalloc_type_view.kt_zv_zv_name = 0x10;
	gSystemInfo.kernelStruct.socket.proto = 0x18;
	gSystemInfo.kernelStruct.socket.usecount = 0x22C;
	gSystemInfo.kernelStruct.protosw.input = 0x28;
	gSystemInfo.kernelStruct.RBLink.rbe_left = 0;
	gSystemInfo.kernelStruct.RBLink.rbe_right = 0x8;
	gSystemInfo.kernelStruct.RBLink.rbe_parent = 0x10;

	// Keep the original beta-kernel threshold as well as the iOS 16 minor gates.
	if (strcmp(darwinVersion, "22.1.0") >= 0 && xnu_version_compare(xnuVersion, (struct xnu_version){ .major = 8792, .minor = 42, .patch = 0 }) >= 0) {
		gSystemInfo.kernelStruct.ipc_space.table_uses_smr = true;
		gSystemInfo.kernelStruct.proc_ro.t_flags_ro = 0x78;
		if (strcmp(darwinVersion, "22.3.0") >= 0) {
			gSystemInfo.kernelConstant.smrBase = 2;
			gSystemInfo.kernelConstant.VM_PAGE_PACKED_PTR_BASE = 0xFFFFFFDC00000000ULL;
			if (strcmp(darwinVersion, "22.4.0") >= 0) {
				gSystemInfo.kernelStruct.proc.flag = 0x454;
				gSystemInfo.kernelStruct.proc.textvp = 0x548;
				if (isArm64e) {
					gSystemInfo.kernelStruct.pmap_cs_code_directory.trust = 0x1EC;
				}
				if (strcmp(darwinVersion, "22.4.0") == 0 && gSystemInfo.kernelStruct.proc.struct_size != 0x730) {
					gSystemInfo.kernelStruct.proc.flag = 0x25C;
					gSystemInfo.kernelStruct.proc.textvp = 0x350;
				}
			}
		}
	}
}
