/*
// ============================================================
// ram_generator.sv
// Generates write and read transactions
// ============================================================

`ifndef RAM_GENERATOR_SV
`define RAM_GENERATOR_SV

`include "ram_transaction.sv"

class ram_generator;

    // -------------------------------------------------------
    // Mailboxes to write/read driver
    // -------------------------------------------------------
    mailbox #(ram_transaction) wr_mbx;      // to write driver
    mailbox #(ram_transaction) rd_mbx;      // to read driver
    mailbox #(bit)             wr_done_mbx; // write driver acks each write

    // -------------------------------------------------------
    // Configuration
    // -------------------------------------------------------
    int unsigned num_writes;    // number of write transactions
    int unsigned num_reads;     // number of read transactions
    int          seed;          // random seed

    // -------------------------------------------------------
    // Constructor
    // -------------------------------------------------------
    function new(mailbox #(ram_transaction) wr_mbx,
                 mailbox #(ram_transaction) rd_mbx,
                 mailbox #(bit)             wr_done_mbx,
                 int unsigned num_writes = 32,
                 int unsigned num_reads  = 32,
                 int          seed       = 0);
        this.wr_mbx      = wr_mbx;
        this.rd_mbx      = rd_mbx;
        this.wr_done_mbx = wr_done_mbx;
        this.num_writes  = num_writes;
        this.num_reads   = num_reads;
        this.seed        = seed;
    endfunction

    // -------------------------------------------------------
    // run() - generate all transactions
    // Writes first (fully drained), then directed reads to
    // the same addresses, then random reads for coverage.
    // -------------------------------------------------------
    task run();
        ram_transaction txn;
        logic [6:0] written_addrs [];
        written_addrs = new[num_writes];

        // --- Phase 1: Write transactions ---
        $display("[GEN] Starting %0d WRITE transactions", num_writes);
        for (int i = 0; i < num_writes; i++) begin
            txn = new();
            txn.op = WRITE;
            if (!txn.randomize() with { op == WRITE; }) begin
                $fatal(1, "[GEN] randomize() failed for WRITE txn %0d", i);
            end
            written_addrs[i] = txn.addr;
            txn.print("[GEN-WR]");
            wr_mbx.put(txn);
        end

        // Wait for all writes to fully complete before issuing any reads.
        // The write driver posts one token per completed write.
        $display("[GEN] Waiting for all %0d writes to drain...", num_writes);
        begin
            bit tok;
            for (int i = 0; i < num_writes; i++)
                wr_done_mbx.get(tok);
        end
        $display("[GEN] All writes done. Starting reads.");

        // --- Phase 2: Directed READ back every written address ---
        $display("[GEN] Starting %0d directed READ-BACK transactions", num_writes);
        for (int i = 0; i < num_writes; i++) begin
            txn = new();
            txn.op   = READ;
            txn.addr = written_addrs[i];
            txn.print("[GEN-RD-DIR]");
            rd_mbx.put(txn);
        end

        // --- Phase 3: Random READ transactions ---
        $display("[GEN] Starting %0d random READ transactions", num_reads);
        for (int i = 0; i < num_reads; i++) begin
            txn = new();
            txn.op = READ;
            if (!txn.randomize() with { op == READ; }) begin
                $fatal(1, "[GEN] randomize() failed for READ txn %0d", i);
            end
            txn.print("[GEN-RD-RND]");
            rd_mbx.put(txn);
        end

        $display("[GEN] All transactions generated.");
    endtask

    // -------------------------------------------------------
    // gen_block_targeted() - hit all 4 decoder blocks evenly
    // -------------------------------------------------------
    task gen_block_targeted(int txns_per_block = 8);
        ram_transaction txn;
        // Block 0: addr 0x00-0x1F, Block 1: 0x20-0x3F
        // Block 2: addr 0x40-0x5F, Block 3: 0x60-0x7F
        logic [6:0] base_addrs [4] = '{7'h00, 7'h20, 7'h40, 7'h60};

        for (int blk = 0; blk < 4; blk++) begin
            for (int i = 0; i < txns_per_block; i++) begin
                txn       = new();
                txn.op    = WRITE;
                txn.addr  = base_addrs[blk] + i[4:0];
                txn.wdata = $urandom_range(0, 255);
                txn.print($sformatf("[GEN-BLK%0d-WR]", blk));
                wr_mbx.put(txn);
            end
        end

        // Drain all writes first
        begin
            bit tok;
            for (int blk = 0; blk < 4; blk++)
                for (int i = 0; i < txns_per_block; i++)
                    wr_done_mbx.get(tok);
        end

        for (int blk = 0; blk < 4; blk++) begin
            for (int i = 0; i < txns_per_block; i++) begin
                txn      = new();
                txn.op   = READ;
                txn.addr = base_addrs[blk] + i[4:0];
                txn.print($sformatf("[GEN-BLK%0d-RD]", blk));
                rd_mbx.put(txn);
            end
        end
    endtask

endclass : ram_generator

`endif // RAM_GENERATOR_SV

*/



// ============================================================
// ram_generator.sv
//
// Single responsibility: own the mailboxes and provide the
// only legal path to inject transactions into the drivers.
//
// env calls run() with addresses and data from the test.
// send_write / send_read / wait_writes_done are internal
// only ? nothing outside this class calls them directly.
// ============================================================

`ifndef RAM_GENERATOR_SV
`define RAM_GENERATOR_SV

`include "ram_transaction.sv"

class ram_generator;

    // -------------------------------------------------------
    // Mailboxes ? private, enforced by compiler
    // -------------------------------------------------------
    local mailbox #(ram_transaction) wr_mbx;
    local mailbox #(ram_transaction) rd_mbx;
    local mailbox #(bit)             wr_done_mbx;

    // -------------------------------------------------------
    // Constructor
    // -------------------------------------------------------
    function new(mailbox #(ram_transaction) wr_mbx,
                 mailbox #(ram_transaction) rd_mbx,
                 mailbox #(bit)             wr_done_mbx);
        this.wr_mbx      = wr_mbx;
        this.rd_mbx      = rd_mbx;
        this.wr_done_mbx = wr_done_mbx;
    endfunction

    // -------------------------------------------------------
    // Internal API ? only run() calls these
    // -------------------------------------------------------

    local task send_write(input logic [6:0] addr, input logic [7:0] data);
        ram_transaction txn = new();
        txn.op    = WRITE;
        txn.addr  = addr;
        txn.wdata = data;
        txn.print("[GEN-WR]");
        wr_mbx.put(txn);
    endtask

    local task wait_writes_done(input int unsigned n);
        bit tok;
        repeat (n) wr_done_mbx.get(tok);
    endtask

    local task send_read(input logic [6:0] addr);
        ram_transaction txn = new();
        txn.op   = READ;
        txn.addr = addr;
        txn.print("[GEN-RD]");
        rd_mbx.put(txn);
    endtask

    // -------------------------------------------------------
    // run() ? single public entry point.
    // Called by env with arguments received from the test.
    //
    // Writes are fully drained before reads are issued so
    // the scoreboard always has expected values in place.
    //
    // For random test: pass empty arrays with n_writes/
    // n_reads counts and randomize flag set.
    // For directed tests: pass explicit addrs/data arrays.
    // -------------------------------------------------------
    task run(
        input logic [6:0] wr_addrs  [],
        input logic [7:0] wr_datas  [],
        input int unsigned            n_writes,
        input logic [6:0] rd_addrs  [],
        input int unsigned            n_reads,
        input bit                     randomize_txns = 0
    );
        // ---- Writes ----
        $display("[GEN] Sending %0d writes", n_writes);
        if (randomize_txns) begin
            for (int i = 0; i < n_writes; i++) begin
                ram_transaction txn = new();
                if (!txn.randomize() with { op == WRITE; })
                    $fatal(1, "[GEN] randomize() failed for WRITE %0d", i);
                send_write(txn.addr, txn.wdata);
            end
        end else begin
            for (int i = 0; i < n_writes; i++)
                send_write(wr_addrs[i], wr_datas[i]);
        end

        // Drain all writes before issuing reads
        wait_writes_done(n_writes);
        $display("[GEN] All writes done");

        // ---- Reads ----
        $display("[GEN] Sending %0d reads", n_reads);
        if (randomize_txns) begin
            for (int i = 0; i < n_reads; i++) begin
                ram_transaction txn = new();
                if (!txn.randomize() with { op == READ; })
                    $fatal(1, "[GEN] randomize() failed for READ %0d", i);
                send_read(txn.addr);
            end
        end else begin
            for (int i = 0; i < n_reads; i++)
                send_read(rd_addrs[i]);
        end

        $display("[GEN] Done");
    endtask

endclass : ram_generator

`endif // RAM_GENERATOR_SV
