`timescale 1ps/1ps

// RISC-V Sv32 Hardware Page Table Walker (PTW)

module PTW (
    input clk,
    input rst_n,

    // MMU / TLB Interface
    input TLB_Miss_in,
    input Dirty_Fault_in,
    input [31:0] Virtual_Address_in,
    
    // Control Registers
    input [31:0] satp_in, // Contains the PPN (Physical Page Number) of the Root Page Table

    // Output back to TLB
    output logic fill_en_out,
    output logic [19:0] fill_virtual_page_out,
    output logic [19:0] fill_physical_page_out,
    output logic fill_dirty_bit_out,
    output logic ptw_busy_out, // Tells the CPU pipeline the PTW is currently walking

    // Memory Interface (Connect to L2 Cache or Memory Arbiter)
    output logic ptw_mem_req_out,
    output logic ptw_mem_write_out,
    output logic [31:0] ptw_mem_addr_out,
    output logic [31:0] ptw_mem_write_data_out,
    input ptw_mem_data_valid_in,
    input [31:0] ptw_mem_read_data_in
);

    // State Machine encoding
    typedef enum logic [3:0] {
        IDLE,
        REQ_L1_PTE,
        WAIT_L1_PTE,
        REQ_L0_PTE,
        WAIT_L0_PTE,
        UPDATE_DIRTY_BIT,
        WAIT_UPDATE,
        FILL_TLB
    } ptw_state_t;

    ptw_state_t state, next_state;

    // Internal registers to hold addresses and PTEs
    logic [31:0] current_va;
    logic is_dirty_fault;
    logic [31:0] l1_pte;
    logic [31:0] l0_pte;
    
    // Sv32 Virtual Address breakdown
    logic [9:0] vpn1;
    logic [9:0] vpn0;
    assign vpn1 = current_va[31:22];
    assign vpn0 = current_va[21:12];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            current_va <= '0;
            is_dirty_fault <= 1'b0;
            l1_pte <= '0;
            l0_pte <= '0;
        end else begin
            state <= next_state;
            
            if (state == IDLE && (TLB_Miss_in || Dirty_Fault_in)) begin
                current_va <= Virtual_Address_in;
                is_dirty_fault <= Dirty_Fault_in;
            end
            
            if (state == WAIT_L1_PTE && ptw_mem_data_valid_in) begin
                l1_pte <= ptw_mem_read_data_in;
            end

            if (state == WAIT_L0_PTE && ptw_mem_data_valid_in) begin
                l0_pte <= ptw_mem_read_data_in;
            end
        end
    end

    always_comb begin
        // Defaults
        next_state = state;
        ptw_mem_req_out = 1'b0;
        ptw_mem_write_out = 1'b0;
        ptw_mem_addr_out = '0;
        ptw_mem_write_data_out = '0;
        
        fill_en_out = 1'b0;
        fill_virtual_page_out = '0;
        fill_physical_page_out = '0;
        fill_dirty_bit_out = 1'b0;
        ptw_busy_out = 1'b1;

        case (state)
            IDLE: begin
                ptw_busy_out = 1'b0;
                if (TLB_Miss_in || Dirty_Fault_in) begin
                    next_state = REQ_L1_PTE;
                end
            end

            REQ_L1_PTE: begin
                ptw_mem_req_out = 1'b1;
                // L1 PTE Address = (satp.PPN * 4096) + (VPN1 * 4)
                ptw_mem_addr_out = {satp_in[19:0], 12'b0} + {20'b0, vpn1, 2'b00};
                next_state = WAIT_L1_PTE;
            end

            WAIT_L1_PTE: begin
                if (ptw_mem_data_valid_in) begin
                    // Note: Skipping Valid/Permission bit checks for prototype simplicity
                    next_state = REQ_L0_PTE;
                end
            end

            REQ_L0_PTE: begin
                ptw_mem_req_out = 1'b1;
                // L0 PTE Address = (L1_PTE.PPN * 4096) + (VPN0 * 4)
                ptw_mem_addr_out = {l1_pte[29:10], 12'b0} + {20'b0, vpn0, 2'b00};
                next_state = WAIT_L0_PTE;
            end

            WAIT_L0_PTE: begin
                if (ptw_mem_data_valid_in) begin
                    if (is_dirty_fault || !ptw_mem_read_data_in[7]) begin // PTE[7] is Dirty bit
                        next_state = UPDATE_DIRTY_BIT;
                    end else begin
                        next_state = FILL_TLB;
                    end
                end
            end

            UPDATE_DIRTY_BIT: begin
                ptw_mem_req_out = 1'b1;
                ptw_mem_write_out = 1'b1;
                ptw_mem_addr_out = {l1_pte[29:10], 12'b0} + {20'b0, vpn0, 2'b00};
                // Set the Dirty Bit (bit 7) to 1
                ptw_mem_write_data_out = l0_pte | 32'h0000_0080;
                next_state = WAIT_UPDATE;
            end

            WAIT_UPDATE: begin
                if (ptw_mem_data_valid_in) begin
                    next_state = FILL_TLB;
                end
            end

            FILL_TLB: begin
                fill_en_out = 1'b1;
                fill_virtual_page_out = current_va[31:12];
                fill_physical_page_out = l0_pte[29:10]; // PPN from L0 PTE
                fill_dirty_bit_out = is_dirty_fault ? 1'b1 : l0_pte[7];
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end
endmodule