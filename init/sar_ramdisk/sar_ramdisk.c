#include "bootimg.h"
#include "../do_mounts.h"

#include <linux/syscalls.h>

extern void clean_rootfs(void);
extern void flush_delayed_fput(void);
extern char* unpack_to_rootfs(char *buf, unsigned long len);

static int padding(unsigned itemsize, int pagesize) {
	unsigned pagemask = pagesize - 1;

	if((itemsize & pagemask) == 0)
		return 0;

	return pagesize - (itemsize & pagemask);
}

int mount_sar_ramdisk(char* name) {
	struct boot_img_hdr_v1 header;
	unsigned int rd_offset;
	int fd;
	int res = 0;
	char* buf;

	fd = sys_open(name, O_RDONLY, 0);

	if (fd < 0) {
		pr_err("SAR_RD: Failed to open %s: Error %d", name, fd);
		return 0;
	}

	if (sys_read(fd, (char*) &header, sizeof(header)) != sizeof(header)) {
		pr_err("SAR_RD: Failed to read bootimage header");
		goto clean_nobuf;
	}

	rd_offset += sizeof(header);
	rd_offset += padding(sizeof(header), header.page_size);
	rd_offset += header.kernel_size;
	rd_offset += padding(header.kernel_size, header.page_size);

	pr_err("SAR_RD: Trying to load Ramdisk at offset %d", rd_offset);

	if (sys_lseek(fd, rd_offset, 0) != rd_offset) {
		pr_err("SAR_RD: Failed to seek to %d", rd_offset);
		goto clean_nobuf;
	}

	buf = kmalloc(header.ramdisk_size, GFP_KERNEL);

	if (!buf) {
		pr_err("SAR_RD: Out of memory");
		goto clean_nobuf;
	}

	if (sys_read(fd, buf, header.ramdisk_size) != header.ramdisk_size) {
		pr_err("SAR_RD: EOF while trying to read ramdisk!");
		goto clean;
	}

	clean_rootfs();
	res = !unpack_to_rootfs(buf, header.ramdisk_size);
	flush_delayed_fput();
	load_default_modules();

clean:
	kfree(buf);
clean_nobuf:
	sys_close(fd);

	if (res)
		pr_err("SAR_RD: Successfully loaded ramdisk");
	else
		pr_err("SAR_RD: Failed to load ramdisk");

	return res;
}
