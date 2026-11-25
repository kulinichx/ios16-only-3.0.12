#include <assert.h>
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include "Fat.h"
#include "FileStream.h"
#include "CodeDirectory.h"
#include "CSBlob.h"

static MemoryStream stream;
static FileStreamContext context;
static Fat fat;
static MachO slices[3];
static CS_DecodedSuperBlob decoded;
static unsigned currentSlice, visits, mutations, streamFrees, fatFrees, closes;
static int failSignatureSlice, failMutationSlice;
static bool failParse, failStream, unsignedFile, trustedFile, cryptexFile;
static const char *fakePath = "/var/test-plugin.dylib";
static int mock_fcntl(int fd, int cmd, ...)
{
    assert(fd == 7 && cmd == F_GETPATH);
    va_list args; va_start(args,cmd); char *out = va_arg(args,char *); va_end(args);
    strcpy(out, cryptexFile ? "/private/preboot/Cryptexes/test" : fakePath); return 0;
}
static int mock_open(const char *path, int flags, ...) { assert(!strcmp(path,fakePath) && flags == O_RDONLY); return 7; }
static int mock_close(int fd) { assert(fd == 7); closes++; return 0; }
static bool string_has_prefix(const char *s,const char *p) { return !strncmp(s,p,strlen(p)); }
static bool isRemovableBundlePath(const char *path) { (void)path; return false; }
static bool hasTrollstoreLiteMarker(const char *path) { (void)path; return false; }
static bool hasJailFoolsMarker(const char *path) { (void)path; return false; }
static bool macho_is_mappable(MachO *value) { (void)value; return true; }
static bool is_cdhash_trustcached(cdhash_t hash) { (void)hash; return trustedFile; }
int macho_enumerate_load_commands(MachO *value, void (^block)(struct load_command,uint64_t,void *,bool *))
{
    (void)value; if ((int)currentSlice == failSignatureSlice) return -1;
    if (!unsignedFile) { struct load_command cmd = {.cmd = LC_CODE_SIGNATURE}; bool stop=false; block(cmd,0,NULL,&stop); }
    return 0;
}
CS_SuperBlob *macho_read_code_signature(MachO *value) { (void)value; return calloc(1,sizeof(CS_SuperBlob)); }
CS_DecodedSuperBlob *csd_superblob_decode(CS_SuperBlob *value) { assert(value); return &decoded; }
void csd_superblob_free(CS_DecodedSuperBlob *value) { assert(value == &decoded); }
static bool csd_superblob_is_adhoc_signed(CS_DecodedSuperBlob *value) { assert(value == &decoded); return true; }
int csd_superblob_calculate_best_cdhash(CS_DecodedSuperBlob *value, void *hash, int *type)
{ (void)type; assert(value == &decoded); memset(hash,(int)currentSlice+1,CS_CDHASH_LEN); return 0; }
static int ensure_randomized_cdhash_for_slice(const char *path,uint64_t offset,void *hash)
{ (void)hash; assert(!strcmp(path,fakePath) && offset == currentSlice); mutations++; return (int)currentSlice == failMutationSlice ? -1 : 0; }
void fat_enumerate_slices(Fat *value,void (^block)(MachO *,bool *))
{
    assert(value == &fat);
    for (currentSlice=0; currentSlice<3;currentSlice++) { bool stop=false; visits++; block(&slices[currentSlice],&stop); if(stop) break; }
}
MemoryStream *file_stream_init_from_file_descriptor(int fd,uint32_t offset,size_t size,uint32_t flags)
{ (void)size; assert(fd == 7 && offset == 0 && flags == 0); return failStream ? NULL : &stream; }
Fat *fat_init_from_memory_stream(MemoryStream *value) { assert(value == &stream); return failParse ? NULL : &fat; }
void memory_stream_free(MemoryStream *value) { assert(value == &stream); streamFrees++; }
void fat_free(Fat *value) { assert(value == &fat); fatFrees++; streamFrees++; }
#define fcntl mock_fcntl
#define open mock_open
#define close mock_close
/* PRODUCTION_COLLECTION */
#undef fcntl
#undef open
#undef close
static void reset(void)
{
    visits=mutations=streamFrees=fatFrees=closes=0; failSignatureSlice=failMutationSlice=-1;
    failParse=failStream=unsignedFile=trustedFile=cryptexFile=false;
    stream.context=&context; context.fd=7; fat.stream=&stream;
    for(unsigned i=0;i<3;i++) slices[i].archDescriptor.offset=i;
}
int main(void)
{
    cdhash_t *hashes; uint32_t count;
    reset(); assert(file_collect_untrusted_cdhashes_by_path(fakePath,&hashes,&count)==0);
    assert(count==3 && visits==3 && mutations==3 && closes==1 && fatFrees==1);
    for(unsigned i=0;i<3;i++) assert(hashes[i][0]==i+1);
    free(hashes);
    for(unsigned kind=0;kind<2;kind++) {
        reset(); if(kind) failSignatureSlice=1; else failMutationSlice=1;
        hashes=(void *)1; count=123;
        assert(file_collect_untrusted_cdhashes_by_path(fakePath,&hashes,&count)!=0);
        assert(!hashes && !count && visits==2 && closes==1 && fatFrees==1);
    }
    reset(); unsignedFile=true; assert(file_collect_untrusted_cdhashes(7,&hashes,&count)==0); assert(!hashes && !count && !mutations && !closes);
    reset(); trustedFile=true; assert(file_collect_untrusted_cdhashes(7,&hashes,&count)==0); assert(!hashes && !count && !mutations);
    reset(); cryptexFile=true; assert(file_collect_untrusted_cdhashes(7,&hashes,&count)==0); assert(!visits && !count);
    reset(); failParse=true; assert(file_collect_untrusted_cdhashes(7,&hashes,&count)!=0); assert(!hashes && !count && streamFrees==1 && !fatFrees);
    reset(); failStream=true; assert(file_collect_untrusted_cdhashes(7,&hashes,&count)!=0); assert(!hashes && !count && !streamFrees);
    puts("PASS production signature collection failure propagation, partial-result discard, exclusions and cleanup");
}
