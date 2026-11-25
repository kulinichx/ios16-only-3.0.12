// Production signature transaction; real ChOma declarations with fault-injected IO.
#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include "Fat.h"
#include "FileStream.h"
#include "MachO.h"
#include "CodeDirectory.h"
#include "MachOByteOrder.h"

static void audit_log(const char *format, ...) { (void)format; }
#define JBLogDebug(...) audit_log(__VA_ARGS__)
#define JBLogError(...) audit_log(__VA_ARGS__)
#define jbinfo(field) brand
static const uint64_t brand = 0x123456789abcdef0ULL;
static uint8_t bytes[0x10000];
static uint64_t sliceBase;
static size_t writes, streamsFreed, fatsFreed;
static unsigned failWriteNumber;
static bool failParse, failRead, failDecode;
static MemoryStream fileStream, sliceStream;
static Fat fat;
static MachO macho;
static CS_DecodedSuperBlob decoded;
static CS_DecodedBlob blob;
enum { SECTION = sizeof(struct mach_header_64) + sizeof(struct segment_command_64), SIGNATURE = 0x1000,
       BLOB_OFFSET = sizeof(CS_SuperBlob) + sizeof(CS_BlobIndex), DIRECTORY_SIZE = sizeof(CS_CodeDirectory) + 32 };

MemoryStream *file_stream_init_from_path(const char *path, uint32_t start, size_t size, uint32_t flags)
{ (void)path; (void)start; (void)size; (void)flags; return &fileStream; }
Fat *fat_init_from_memory_stream(MemoryStream *stream) { assert(stream == &fileStream); return failParse ? NULL : &fat; }
void memory_stream_free(MemoryStream *stream) { assert(stream == &fileStream); streamsFreed++; }
void fat_free(Fat *value) { assert(value == &fat); fatsFreed++; streamsFreed++; }
MachO *fat_find_preferred_slice(Fat *value) { assert(value == &fat); return &macho; }
void fat_enumerate_slices(Fat *value, void (^block)(MachO *, bool *))
{ assert(value == &fat); bool stop = false; block(&macho, &stop); }
size_t memory_stream_get_size(MemoryStream *stream) { return stream == &sliceStream ? 0x2000 : sizeof(bytes); }
int memory_stream_read(MemoryStream *stream, uint64_t offset, size_t size, void *out)
{ assert(stream == &fileStream); if (failRead) return -1; assert(offset + size <= sizeof(bytes)); memcpy(out, bytes + offset, size); return 0; }
int memory_stream_write(MemoryStream *stream, uint64_t offset, size_t size, const void *in)
{
    assert(stream == &fileStream); assert(offset + size <= sizeof(bytes));
    writes++;
    // Simulate a short/partial write, including the success marker write.
    if (writes == failWriteNumber) { memcpy(bytes + offset, in, size / 2); return -1; }
    memcpy(bytes + offset, in, size); return 0;
}
int macho_read_at_offset(MachO *value, uint64_t offset, size_t size, void *out)
{ assert(value == &macho); return memory_stream_read(&fileStream, sliceBase + offset, size, out); }
int macho_enumerate_load_commands(MachO *value, void (^block)(struct load_command, uint64_t, void *, bool *))
{
    assert(value == &macho); bool stop = false;
    struct segment_command_64 *seg = (void *)(bytes + sliceBase + sizeof(struct mach_header_64));
    struct linkedit_data_command *cs = (void *)(bytes + sliceBase + SECTION + sizeof(struct section_64));
    block(*(struct load_command *)seg, sizeof(struct mach_header_64), seg, &stop);
    if (!stop) block(*(struct load_command *)cs, SECTION + sizeof(struct section_64), cs, &stop);
    return 0;
}
CS_SuperBlob *macho_read_code_signature(MachO *value)
{
    assert(value == &macho);
    size_t size = BLOB_OFFSET + DIRECTORY_SIZE;
    CS_SuperBlob *copy = malloc(size); assert(copy);
    memcpy(copy, bytes + sliceBase + SIGNATURE, size); return copy;
}
CS_DecodedSuperBlob *csd_superblob_decode(CS_SuperBlob *value) { (void)value; return failDecode ? NULL : &decoded; }
void csd_superblob_free(CS_DecodedSuperBlob *value) { assert(value == &decoded); }
CS_DecodedBlob *csd_superblob_find_best_code_directory(CS_DecodedSuperBlob *value) { assert(value == &decoded); return &blob; }
size_t csd_blob_get_size(CS_DecodedBlob *value) { assert(value == &blob); return DIRECTORY_SIZE; }
int csd_blob_read(CS_DecodedBlob *value, uint64_t offset, size_t size, void *out)
{ assert(value == &blob); return memory_stream_read(&fileStream, sliceBase + SIGNATURE + BLOB_OFFSET + offset, size, out); }
static bool isRemovableBundlePath(const char *path) { (void)path; return false; }
static bool hasTrollstoreLiteMarker(const char *path) { (void)path; return false; }
static bool hasJailFoolsMarker(const char *path) { (void)path; return false; }

/* PRODUCTION_FUNCTIONS */

static void reset(uint64_t base)
{
    memset(bytes, 0, sizeof(bytes)); sliceBase = base;
    writes = streamsFreed = fatsFreed = failWriteNumber = 0;
    failParse = failRead = failDecode = false;
    fat.stream = &fileStream; macho.stream = &sliceStream; macho.archDescriptor.offset = base;
    blob.type = CSSLOT_CODEDIRECTORY;
    struct segment_command_64 *seg = (void *)(bytes + base + sizeof(struct mach_header_64));
    seg->cmd = LC_SEGMENT_64; seg->cmdsize = sizeof(*seg) + sizeof(struct section_64); seg->nsects = 1;
    strcpy(seg->segname, "__TEXT");
    struct section_64 *section = (void *)(bytes + base + SECTION); strcpy(section->segname, "__TEXT");
    struct linkedit_data_command *link = (void *)(bytes + base + SECTION + sizeof(*section));
    link->cmd = LC_CODE_SIGNATURE; link->cmdsize = sizeof(*link); link->dataoff = SIGNATURE; link->datasize = BLOB_OFFSET + DIRECTORY_SIZE;
    CS_SuperBlob *super = (void *)(bytes + base + SIGNATURE);
    super->magic = OSSwapHostToBigInt32(CSMAGIC_EMBEDDED_SIGNATURE);
    super->length = OSSwapHostToBigInt32(BLOB_OFFSET + DIRECTORY_SIZE); super->count = OSSwapHostToBigInt32(1);
    super->index[0].type = OSSwapHostToBigInt32(CSSLOT_CODEDIRECTORY); super->index[0].offset = OSSwapHostToBigInt32(BLOB_OFFSET);
    CS_CodeDirectory dir = {.magic = CSMAGIC_CODEDIRECTORY, .length = DIRECTORY_SIZE, .version = 0x20200,
        .hashOffset = sizeof(CS_CodeDirectory), .nCodeSlots = 1, .codeLimit = SIGNATURE, .hashType = CS_HASHTYPE_SHA256_256, .hashSize = 32, .pageSize = 12};
    CODE_DIRECTORY_APPLY_BYTE_ORDER(&dir, HOST_TO_BIG_APPLIER);
    memcpy(bytes + base + SIGNATURE + BLOB_OFFSET, &dir, sizeof(dir));
}
static void verify(void)
{
    uint64_t value; memcpy(&value, bytes + sliceBase + SECTION + offsetof(struct section_64, segname) + 8, 8);
    assert(value == brand);
    uint8_t hash[32]; CC_SHA256(bytes + sliceBase, SIGNATURE, hash);
    assert(!memcmp(hash, bytes + sliceBase + SIGNATURE + BLOB_OFFSET + sizeof(CS_CodeDirectory), sizeof(hash)));
}
int main(int argc, char **argv)
{
    assert(argc == 2); // Existing writable temporary file used only for stat/access.
    uint8_t before[sizeof(bytes)], output[CS_CDHASH_LEN];
    for (unsigned offsetCase = 0; offsetCase < 2; offsetCase++) {
        uint64_t base = offsetCase ? 0x4000 : 0;
        reset(base); memset(output, 0x55, sizeof(output));
        assert(ensure_randomized_cdhash_for_slice(argv[1], base, output) == 0); verify();
        assert(writes == 2 && fatsFreed == 1 && streamsFreed == 1);
        memcpy(before, bytes, sizeof(bytes)); writes = 0;
        assert(ensure_randomized_cdhash_for_slice(argv[1], base, NULL) == 0);
        assert(writes == 0 && !memcmp(before, bytes, sizeof(bytes)));
        // Existing marker with a stale hash must be repaired on retry.
        bytes[base + SIGNATURE + BLOB_OFFSET + sizeof(CS_CodeDirectory)] ^= 0x80;
        assert(ensure_randomized_cdhash_for_slice(argv[1], base, NULL) == 0); verify();
        for (unsigned fail = 1; fail <= 2; fail++) {
            reset(base); memcpy(before, bytes, sizeof(bytes)); memset(output, 0x55, sizeof(output)); failWriteNumber = fail;
            assert(ensure_randomized_cdhash_for_slice(argv[1], base, output) != 0);
            assert(!memcmp(before, bytes, sizeof(bytes)));
            for (unsigned i = 0; i < sizeof(output); i++) assert(output[i] == 0x55);
            failWriteNumber = 0;
            assert(ensure_randomized_cdhash_for_slice(argv[1], base, output) == 0); verify();
        }
        reset(base); failRead = true; assert(ensure_randomized_cdhash_for_slice(argv[1], base, NULL) != 0); assert(writes == 0);
        reset(base); failParse = true; assert(ensure_randomized_cdhash_for_slice(argv[1], base, NULL) != 0); assert(streamsFreed == 1 && !fatsFreed);
        reset(base); failDecode = true; assert(ensure_randomized_cdhash_for_slice(argv[1], base, NULL) != 0); assert(writes == 0 && streamsFreed == 1);
        reset(base);
        CS_CodeDirectory *dir = (void *)(bytes + base + SIGNATURE + BLOB_OFFSET); dir->hashSize = 255;
        assert(ensure_randomized_cdhash_for_slice(argv[1], base, NULL) != 0); assert(writes == 0);
        reset(base); CS_SuperBlob *super = (void *)(bytes + base + SIGNATURE); super->index[0].offset = OSSwapHostToBigInt32(UINT32_MAX);
        assert(ensure_randomized_cdhash_for_slice(argv[1], base, NULL) != 0); assert(writes == 0);
    }
    puts("PASS production signature transaction, partial writes, retry, range rejection and stream cleanup");
    return 0;
}
