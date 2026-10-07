//
//  dumpdecrypted.c
//  在目标进程内解密当前已加载的所有加密镜像（主程序 + 内嵌 Framework + 扩展 appex）
//
//  原理：App Store 应用经过 FairPlay 加密，磁盘上的 __TEXT 等段为密文；
//  但 dyld 加载到内存后会解密。本 dylib 以 DYLD_INSERT_LIBRARIES 方式注入目标进程，
//  在构造函数里遍历所有已加载镜像，把内存中的明文逐段写回文件，并将 cryptid 置 0。
//
//  环境变量：
//    DUMP_OUTPUT_DIR    必填，解密产物输出根目录
//    DUMP_BUNDLE_ROOT   必填，仅解密该路径前缀下的镜像（避免误处理系统库）
//
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <mach-o/loader.h>
#include <mach-o/dyld.h>
#include <mach/vm_prot.h>
#include <limits.h>

static const char *g_out_dir = NULL;
static const char *g_bundle_root = NULL;

static void ensure_parent(const char *path) {
    char tmp[PATH_MAX];
    size_t len = strnlen(path, PATH_MAX - 1);
    memcpy(tmp, path, len);
    tmp[len] = '\0';
    for (size_t i = 1; i < len; i++) {
        if (tmp[i] == '/') {
            tmp[i] = '\0';
            mkdir(tmp, 0755);
            tmp[i] = '/';
        }
    }
    mkdir(tmp, 0755);
}

static void log_line(const char *fmt, ...) {
    if (!g_out_dir) return;
    char path[PATH_MAX];
    snprintf(path, sizeof(path), "%s/.dump.log", g_out_dir);
    FILE *f = fopen(path, "a");
    if (!f) return;
    va_list ap; va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fprintf(f, "\n");
    fclose(f);
}

static void dump_image(uint32_t index) {
    const struct mach_header *mh = _dyld_get_image_header(index);
    const char *path = _dyld_get_image_name(index);
    if (!mh || !path) return;
    if (mh->magic != MH_MAGIC_64) return;          // 仅处理 64 位
    if (g_bundle_root && strncmp(path, g_bundle_root, strlen(g_bundle_root)) != 0) return;

    struct mach_header_64 *hdr = (struct mach_header_64 *)mh;
    uint64_t slide = _dyld_get_image_vmaddr_slide(index);

    // 查找加密命令
    struct load_command *lc = (struct load_command *)((uint8_t *)hdr + sizeof(*hdr));
    struct encryption_info_command_64 *enc = NULL;
    for (uint32_t i = 0; i < hdr->ncmds; i++) {
        if (lc->cmd == LC_ENCRYPTION_INFO_64) {
            struct encryption_info_command_64 *e = (struct encryption_info_command_64 *)lc;
            if (e->cryptid != 0) { enc = e; break; }
        }
        lc = (struct load_command *)((uint8_t *)lc + lc->cmdsize);
    }
    if (!enc) return; // 该镜像未加密，跳过

    // 计算输出相对路径
    const char *rel = path;
    if (g_bundle_root) {
        rel = path + strlen(g_bundle_root);
        while (*rel == '/') rel++;
    }
    char outpath[PATH_MAX];
    snprintf(outpath, sizeof(outpath), "%s/%s", g_out_dir, rel);
    ensure_parent(outpath);

    int fd = open(path, O_RDONLY);
    if (fd < 0) { log_line("open 失败: %s", path); return; }
    struct stat st;
    if (fstat(fd, &st) != 0) { close(fd); return; }
    void *orig = malloc((size_t)st.st_size);
    if (!orig) { close(fd); return; }
    if (pread(fd, orig, (size_t)st.st_size, 0) != (ssize_t)st.st_size) {
        log_line("读取原文件失败: %s", path);
        free(orig); close(fd); return;
    }
    close(fd);

    int ofd = open(outpath, O_RDWR | O_CREAT | O_TRUNC, 0755);
    if (ofd < 0) { log_line("创建输出失败: %s", outpath); free(orig); return; }
    if (ftruncate(ofd, st.st_size) != 0) {
        log_line("ftruncate 失败: %s", outpath);
        free(orig); close(ofd); return;
    }
    if (pwrite(ofd, orig, (size_t)st.st_size, 0) != (ssize_t)st.st_size) {
        log_line("写入原文件失败: %s", outpath);
        free(orig); close(ofd); return;
    }

    // 用内存中的明文覆盖各可读段
    lc = (struct load_command *)((uint8_t *)hdr + sizeof(*hdr));
    for (uint32_t i = 0; i < hdr->ncmds; i++) {
        if (lc->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *sg = (struct segment_command_64 *)lc;
            if (sg->initprot & VM_PROT_READ) {
                uint64_t vaddr = sg->vmaddr + slide;
                uint64_t foff = sg->fileoff;
                uint64_t fsize = sg->filesize;
                if (foff + fsize > (uint64_t)st.st_size) {
                    if (foff >= (uint64_t)st.st_size) continue;
                    fsize = (uint64_t)st.st_size - foff;
                }
                if (fsize > 0) {
                    pwrite(ofd, (const void *)(uintptr_t)vaddr, (size_t)fsize, (off_t)foff);
                }
            }
        }
        lc = (struct load_command *)((uint8_t *)lc + lc->cmdsize);
    }

    // 清除加密标记
    long enc_off = (uint8_t *)enc - (uint8_t *)hdr;
    int zero = 0;
    pwrite(ofd, &zero, 4, enc_off + 8);   // cryptoff
    pwrite(ofd, &zero, 4, enc_off + 12);  // cryptsize
    pwrite(ofd, &zero, 4, enc_off + 16);  // cryptid

    free(orig);
    close(ofd);
    log_line("已解密: %s -> %s", path, outpath);
}

__attribute__((constructor))
static void decrypt_entry(void) {
    g_out_dir = getenv("DUMP_OUTPUT_DIR");
    g_bundle_root = getenv("DUMP_BUNDLE_ROOT");
    if (!g_out_dir) return;

    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        dump_image(i);
    }

    char done[PATH_MAX];
    snprintf(done, sizeof(done), "%s/.dump_done", g_out_dir);
    int fd = open(done, O_CREAT | O_WRONLY, 0644);
    if (fd >= 0) close(fd);

    // 解密已完成，直接退出，避免目标 App 真正启动
    _exit(0);
}
