/*
 * Copyright (c) 2021-2024 Tim Zimmermann  <tim@linux4.de>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "bootimg.h"
#include "../do_mounts.h"

#include <linux/syscalls.h>

extern void clean_rootfs(void);
extern void flush_delayed_fput(void);
extern char* unpack_to_rootfs(char *buf, unsigned long len);

__init int mount_sar_ramdisk(char* name) {
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

	rd_offset += round_up(sizeof(header), header.page_size);
	rd_offset += round_up(header.kernel_size, header.page_size);

	pr_err("SAR_RD: Trying to load Ramdisk at offset %d", rd_offset);

	if (sys_lseek(fd, rd_offset, 0) != rd_offset) {
		pr_err("SAR_RD: Failed to seek to %d", rd_offset);
		goto clean_nobuf;
	}

	buf = kvmalloc(header.ramdisk_size, GFP_KERNEL);

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
	kvfree(buf);
clean_nobuf:
	sys_close(fd);

	if (res)
		pr_err("SAR_RD: Successfully loaded ramdisk");
	else
		pr_err("SAR_RD: Failed to load ramdisk");

	return res;
}
