#include <archive.h>
#include <archive_entry.h>
#include <assert.h>
#include <errno.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
static bool warnHeader;
static int write_header(struct archive *a, struct archive_entry *entry) {
    return warnHeader ? ARCHIVE_WARN : archive_write_header(a,entry);
}
#define archive_write_header write_header
/* PRODUCTION_ARCHIVE */
#undef archive_write_header

static void entry(struct archive *a, const char *name, const char *hardlink, const char *symlink) {
    struct archive_entry *e=archive_entry_new(); assert(e);
    archive_entry_set_pathname(e,name);
    archive_entry_set_perm(e,0644);
    archive_entry_set_filetype(e,symlink ? AE_IFLNK : AE_IFREG);
    if(hardlink) archive_entry_set_hardlink(e,hardlink);
    if(symlink) archive_entry_set_symlink(e,symlink);
    archive_entry_set_size(e,(hardlink || symlink) ? 0 : 4);
    assert(archive_write_header(a,e)==ARCHIVE_OK);
    if(!hardlink && !symlink) assert(archive_write_data(a,"test",4)==4);
    archive_entry_free(e);
}
static struct archive *start(const char *path) {
    struct archive *a=archive_write_new(); assert(a);
    assert(archive_write_set_format_pax_restricted(a)==ARCHIVE_OK);
    assert(archive_write_open_filename(a,path)==ARCHIVE_OK);
    return a;
}
static void finish(struct archive *a) { assert(archive_write_close(a)==ARCHIVE_OK); assert(archive_write_free(a)==ARCHIVE_OK); }
int main(int argc,const char **argv) {
    assert(argc==2);
    char tar[PATH_MAX],out[PATH_MAX],alias[PATH_MAX],name[PATH_MAX],outside[PATH_MAX];
    assert(snprintf(tar,sizeof(tar),"%s/input.tar",argv[1])<(int)sizeof(tar));
    assert(snprintf(out,sizeof(out),"%s/output",argv[1])<(int)sizeof(out));
    assert(snprintf(alias,sizeof(alias),"%s/alias",argv[1])<(int)sizeof(alias));
    assert(snprintf(outside,sizeof(outside),"%s/outside",argv[1])<(int)sizeof(outside));
    assert(mkdir(outside,0755)==0);
    struct archive *a=start(tar);
    entry(a,"nested/original",NULL,NULL); entry(a,"nested/hard","nested/original",NULL);
    entry(a,"system-link",NULL,"/System/Library"); finish(a);
    assert(libarchive_unarchive(tar,out)==0);
    assert(symlink(out,alias)==0);
    assert(libarchive_unarchive(tar,alias)==0);
    struct stat first,second;
    snprintf(name,sizeof(name),"%s/nested/original",out); assert(stat(name,&first)==0);
    snprintf(name,sizeof(name),"%s/nested/hard",out); assert(stat(name,&second)==0 && first.st_ino==second.st_ino);
    a=start(tar); entry(a,"../outside/escape",NULL,NULL); finish(a);
    assert(libarchive_unarchive(tar,out)!=0);
    snprintf(name,sizeof(name),"%s/escape",outside); assert(access(name,F_OK)!=0);
    a=start(tar); entry(a,"redirect",NULL,outside); entry(a,"redirect/escape",NULL,NULL); finish(a);
    assert(libarchive_unarchive(tar,out)!=0 && access(name,F_OK)!=0);
    a=start(tar); entry(a,"warning",NULL,NULL); finish(a); warnHeader=true;
    assert(libarchive_unarchive(tar,out)!=0); warnHeader=false;
    assert(libarchive_unarchive("/nonexistent-rh-test-archive",out)!=0);
    assert(libarchive_unarchive(NULL,out)!=0);
    puts("PASS real libarchive extraction, root alias, hardlinks, absolute symlink target, traversal and writer warning");
}
