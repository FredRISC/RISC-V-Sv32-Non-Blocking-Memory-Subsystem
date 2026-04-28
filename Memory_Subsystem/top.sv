`timescale 1ns/1ps

`define XLEN 32
`define PAGE_WIDTH 12 // 4KB per page
`define CacheLineSize 64   // 64 bytes per line
`define L1CacheSize 2**12 // 4KB
`define NUM_OF_WAYS 4     // 4-way associative cache
`define NUM_OF_SETS  `L1CacheSize/ (`NUM_OF_WAYS*`CacheLineSize) // 16 sets
`define INDEX_BITS $clog2(`NUM_OF_SETS)
`define OFFSET_BITS $clog2(`CacheLineSize)
`define TAG_BITS `XLEN - `INDEX_BITS - `OFFSET_BITS
`define BLOCK_ID_SIZE `TAG_BITS+`INDEX_BITS
`define LSQ_SIZE 16

module top_module(
    input clk,
    input rst_n,
    input flush,

    // CPU Interface
    input [`XLEN-1:0] virtual_address_in, // Provides Virtual Index & Offset
    output TLB_physical_tag_valid_out,

    input [$clog2(`LSQ_SIZE)-1:0] lsq_tag_in,
    input load_req_in,
    output [`XLEN-1:0] load_data_out,
    output load_data_valid_out,
    output load_port_stall_out,

    input store_req_in,
    input [`XLEN-1:0] store_data_in,
    input [3:0] store_byte_en_in, 
    output store_port_stall_out,

    output [`LSQ_SIZE-1:0] lsq_wakeup_vector_out,
    
    // L2 interface 
        // cache block request
    output [`BLOCK_ID_SIZE-1:0] L2_req_block_id_out, 
    output L2_block_req_out,
        // cache block return
    input L2_return_block_valid_in,
    input [`BLOCK_ID_SIZE-1:0] L2_return_block_id_in,
    input [`CacheLineSize-1:0][7:0] L2_return_block_data_in,
        // cache block eviction
    output L2_evict_block_valid_out, // Write-back dirty lines
    output [`BLOCK_ID_SIZE-1:0] L2_evict_block_id_out,
    output [`CacheLineSize-1:0][7:0] L2_evict_block_data_out,

    // MMU Interface
    input [31:0] flush_vaddr_in,       // From sfence.vma rs1
    input [8:0] flush_asid_in,         // From sfence.vma rs2
    input flush_vaddr_valid_in,        // 1 if rs1 != x0
    input flush_asid_valid_in,         // 1 if rs2 != x0
    output Physical_Page_ID_Miss_out,  // debug: TLB miss flag from TLB
    output page_fault_out,
    input [31:0] satp_in, // RISC-V CSR storing the root PTE frame of a process

    // PTW-Memory Interface (Route to L2 Arbiter)
    output ptw_busy_out, // debug: PTW is currently walking
    output ptw_mem_req_valid_out,
    output ptw_mem_req_type_out, // 1 for write, 0 for read
    output [31:0] ptw_mem_addr_out, // physical memory address of a L1 PTE, a L0 PTE or of the translated physical address to be filled into TLB 
    output [31:0] ptw_mem_write_data_out, // for updating the dirty bit of the PTE 
    input ptw_mem_data_valid_in, 
    input [31:0] ptw_mem_read_data_in // The returned L1 PTE, L0 PTE or the translated physical address
);

logic [`TAG_BITS-1:0] MMU_physical_tag_out; // From MMU/TLB
logic MMU_physical_tag_valid_out;           // From MMU/TLB

L1Cache L1Cache_inst(
    // Global signals
    .clk(clk),
    .rst_n(rst_n),
    .flush(flush),
    // CPU Interface
    .virtual_address_in(virtual_address_in),
    .lsq_tag_in(lsq_tag_in),
    .load_req_in(load_req_in),
    .load_data_out(load_data_out),
    .load_data_valid_out(load_data_valid_out),
    .load_port_stall_out(load_port_stall_out),
    .store_req_in(store_req_in),
    .store_data_in(store_data_in),
    .store_byte_en_in(store_byte_en_in),
    .store_port_stall_out(store_port_stall_out),
    .TLB_physical_tag_valid_out(TLB_physical_tag_valid_out),
    .lsq_wakeup_vector_out(lsq_wakeup_vector_out),

    // MMU Interface
    .physical_tag_in(MMU_physical_tag_out),
    .physical_tag_valid_in(MMU_physical_tag_valid_out),

    // L2 Interface
    .L2_req_block_id_out(L2_req_block_id_out),
    .L2_block_req_out(L2_block_req_out),
    .L2_return_block_valid_in(L2_return_block_valid_in),
    .L2_return_block_id_in(L2_return_block_id_in),
    .L2_return_block_data_in(L2_return_block_data_in),
    .L2_evict_block_valid_out(L2_evict_block_valid_out),
    .L2_evict_block_id_out(L2_evict_block_id_out),
    .L2_evict_block_data_out(L2_evict_block_data_out)
);


MMU MMU_inst(
    .clk(clk),
    .rst_n(rst_n),
    // Flush signals
    .flush(flush),
    .flush_vaddr_in(flush_vaddr_in),
    .flush_asid_in(flush_asid_in),
    .flush_vaddr_valid_in(flush_vaddr_valid_in),
    .flush_asid_valid_in(flush_asid_valid_in),
    // CPU Interface
    .Virtual_Address_in(virtual_address_in),
    .load_req_in(load_req_in),
    .store_req_in(store_req_in),
    .Physical_Page_ID_Miss_out(Physical_Page_ID_Miss_out), // debug: TLB miss flag
    .page_fault_out(page_fault_out),
    .satp_in(satp_in),
    // PTW-Memory Interface (Route to L2 Arbiter)
    .ptw_busy_out(ptw_busy_out),   
    .ptw_mem_req_valid_out(ptw_mem_req_valid_out),
    .ptw_mem_req_type_out(ptw_mem_req_type_out),
    .ptw_mem_addr_out(ptw_mem_addr_out),
    .ptw_mem_write_data_out(ptw_mem_write_data_out),
    .ptw_mem_data_valid_in(ptw_mem_data_valid_in),
    .ptw_mem_read_data_in(ptw_mem_read_data_in),
    // Cache Interface
    .physical_tag_out(MMU_physical_tag_out),
    .physical_tag_valid_out(MMU_physical_tag_valid_out)
);


endmodule