#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
enum { off_task_map=1, off_vm_map_pmap=2, off_pmap_ttep=3 };
#define koffsetof(type,field) off_##type##_##field
static unsigned failStage, writes;
static uint64_t proc_task(uint64_t proc) { assert(proc==100); return failStage==1 ? 0 : 200; }
static uint64_t kread_ptr(uint64_t ptr) {
    if(ptr==201) return failStage==2 ? 0 : 300;
    assert(ptr==302); return failStage==3 ? 0 : 400;
}
static uint64_t kread64(uint64_t ptr) { assert(ptr==403); return failStage==4 ? 0 : 500; }
static int vwritebuf(uint64_t ttep,const void *addr,const void *data,size_t length) {
    assert(ttep==500 && addr==(void *)600 && data==(void *)700 && length==800);
    writes++; return -17;
}
/* PRODUCTION_PROC_VWRITE */
int main(void) {
    assert(proc_vwritebuf(100,(void *)600,(void *)700,800)==-17 && writes==1);
    for(failStage=1;failStage<=4;failStage++)
        assert(proc_vwritebuf(100,(void *)600,(void *)700,800)==-1 && writes==1);
    puts("PASS process virtual writes delegate to page-table writer exactly once and stop on missing links");
}
