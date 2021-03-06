/*****************************************************************
*	entry.s
*	by Zhiyi Huang, hzy@cs.otago.ac.nz
*	University of Otago
*
********************************************************************/

.section .init
.globl _start
_start:

b entry  /* branch to the actual entry code */

.section .data

.align 4
.globl font
font:
	.incbin "font1.bin"

.align 4
.global _binary_initcode_start
_binary_initcode_start:
	.incbin "initcode"
.global _binary_initcode_end
_binary_initcode_end:

.align 4
.global _binary_fs_img_start
_binary_fs_img_start:
        .incbin "fs.img"
.global _binary_fs_img_end
_binary_fs_img_end:


.section .text

entry:

/* interrupts disabled, SVC mode by setting PSR_DISABLE_IRQ|PSR_DISABLE_FIQ|PSR_MODE_SVC */

mov r1, #0x00000080 /* PSR_DISABLE_IRQ */
orr r1, #0x00000040 /* PSR_DISABLE_FIQ */
orr r1, #0x00000013 /* PSR_MODE_SVC */
msr cpsr, r1

mov sp, #0x3000
mov r5, #0
mov r6, #0
mov r7, #0
mov r8, #0
	
// store multiple at r4.
stmia r4!, {r5-r8}


/* The majority of the following code comes from "Migrating a software application
   from ARMv5 to ARMv7-A/R", Section 4.1.1. A Document URL is as follows:

   http://infocenter.arm.com/help/topic/com.arm.doc.dai0425/
        DAI0425_migrating_an_application_from_ARMv5_to_ARMv7_AR.pdf  */

// =========== START =========== //

/* Disable MMU */
mrc p15, 0, r1, c1, c0, 0 //Read Control Register configuration data
bic r1, r1, #0x1
mcr p15, 0, r1, c1, c0, 0 //Write Control Register configuration data

/* Disable L1 Caches */
mrc p15, 0, r1, c1, c0, 0 //Read Control Register configuration data
bic r1, r1, #(0x1 << 12)  //Disable Instruction Cache
bic r1, r1, #(0x1 << 2)   //Disable Data Cache
mcr p15, 0, r1, c1, c0, 0 //Write Control Register configuration data

/* Invalidate L1 and Instruction cache */
mov r1, #0                
mcr p15, 0, r1, c7, c5, 0 

/* Invalidate Data cache 
   To make the code general purpose, calculate the cache size first,
   and loop through each set + way */
mrc p15, 1, r0, c0, c0, 0 //Read cache size ID
ldr r3,=0x1ff
and r0, r3, r0, lsr #13   //r0 = no. of sets - 1


	mov r1, #0                //r1 = way counter way_loop
way_loop:
	mov r3, #0                //r3 = set counter set_loop
set_loop:
	mov r2, r1, lsl #30        
	orr r2, r3, lsl #5        //r2 = set/way cache operation format
	mcr p15, 0, r2, c7, c6, 2 //Invalidate the line described by r2
	add r3, r3, #1            //Increment set counter
	cmp r0, r3                //Last set reached yet?
	bgt set_loop              //If not, iterate set_loop
	add r1, r1, #1            //else next
	cmp r1, #4                //Last way reached yet?
	bne way_loop              //If not, iterate way_loop


/* Invalidate TLB */
mcr p15, 0, r1, c8, c7, 0

/* Branch Prediction Enable */
mov r1, #0
mrc p15, 0, r1, c1, c0, 0 //Read Control Register configuration data
orr r1, r1, #(0x1 << 11)  //Global BP Enable bit
mcr p15, 0, r1, c1, c0, 0 //Write Control Register configuration data

/* Enable D-side Prefetch */
mrc p15, 0, r1, c1, c0, 1 //Read Anxiliary Control Register
orr r1, r1, #(0x1 << 2)   //Enable D-side prefetch
mcr p15, 0, r1, c1, c0, 1 //Write Anxiliary Control Register
dsb
isb
 
/* Jump to mmuinit0 in mmu.c */
bl mmuinit0       

/* Initialize MMU */
mov r1, #0x0
mcr p15, 0, r1, c2, c0, 2 //Write Translation Table Base Control Register
ldr r1, =0x4000           //0x4000 == ttb address
mcr p15, 0, r1, c2, c0, 0 //Write Translation Table Base Register 0

/* Set domain access control register */
ldr r1,=0xffffffff        //Full Access to all domains (should be fixed later)
mcr p15, 0, r1, c3, c0, 0 //Write Domain Access Control Register


/* Enable MMU */
mrc p15, 0, r1, c1, c0, 0 //Read Control Register configuration data
orr r1, r1, #0x1          //Bit 0 is the MMU enable
orr r1, #0x00002000       //Vector table at high memory
orr r1, #0x00000004       //Data Cache Enable
orr r1, #0x00001000       //Instruction Cache Enable
mcr p15, 0, r1, c1, c0, 0 //Write Control Register configuration data

// =========== END =========== //
       


/* switch SP and PC into KZERO space */
mov r1, sp
add r1, #0x80000000
mov sp, r1


ldr r1, =_pagingstart
bx r1

.global _pagingstart
_pagingstart:
bl cmain  /* call C functions now */
bl NotOkLoop

.global dsb_barrier
dsb_barrier:
    dsb
	bx lr
.global flush_dcache_all
flush_dcache_all:
	mov r0, #0
	//mcr p15, 0, r0, c7, c10, 4 /* dsb */
	dsb
    mov r0, #0
	mcr p15, 0, r0, c7, c14, 0 /* invalidate d-cache */
	bx lr
.global flush_idcache
flush_idcache:
	//mov r0, #0
	//mcr p15, 0, r0, c7, c10, 4 /* dsb */
    dsb
	mov r0, #0
	mcr p15, 0, r0, c7, c14, 0 /* invalidate d-cache */
	mov r0, #0
	mcr p15, 0, r0, c7, c5, 0 /* invalidate i-cache */
	bx lr

.global flush_icache /* This is not a builtin function */
flush_icache:
	mov r0, #0
	mcr p15, 0, r0, c7, c5, 0
	bx lr

.global flush_tlb
flush_tlb:
	mov r0, #0
	mcr p15, 0, r0, c8, c7, 0
    dsb 
	//mcr p15, 0, r0, c7, c10, 4
	bx lr
.global flush_dcache /* flush a range of data cache flush_dcache(va1, va2) */
flush_dcache:
	mcrr p15, 0, r0, r1, c14
	bx lr
.global set_pgtbase /* set the page table base set_pgtbase(base) */
set_pgtbase:
	mcr p15, 0, r0, c2, c0
	bx lr

.global getsystemtime
getsystemtime:
	ldr r0, =0xFE003004 /* addr of the time-stamp lower 32 bits */
        ldrd r0, r1, [r0]
	bx lr