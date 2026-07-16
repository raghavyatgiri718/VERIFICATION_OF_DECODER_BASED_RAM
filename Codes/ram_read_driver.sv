// ============================================================
// ram_read_driver.sv
// Drives READ transactions onto the DUT via the interface
// ============================================================

`ifndef RAM_READ_DRIVER_SV
`define RAM_READ_DRIVER_SV

`include "ram_transaction.sv"

class ram_read_driver;

    virtual ram_if.READ_DRV vif;

    mailbox #(ram_transaction) rd_mbx;
    mailbox #(ram_transaction) rd_done_mbx;

    int unsigned txn_count;

    function new(virtual ram_if.READ_DRV vif,
                 mailbox #(ram_transaction) rd_mbx,
                 mailbox #(ram_transaction) rd_done_mbx);
        this.vif         = vif;
        this.rd_mbx      = rd_mbx;
        this.rd_done_mbx = rd_done_mbx;
        this.txn_count   = 0;
    endfunction

    task run();
        ram_transaction txn;
        $display("[RD-DRV] Started");
        forever begin
            rd_mbx.get(txn);
            drive(txn);
            txn_count++;
        end
    endtask

    // -------------------------------------------------------
    // Timing analysis (10 ns clock, output #1 skew):
    //
    //  posedge:  T0        T10       T20       T30
    //            |         |         |         |
    //  @rd_cb fires at T0, T10, T20...
    //  Assign re<=1 at @T0  -> wire re goes 1 at T0+1 = T1
    //  DUT posedge T10: sees re=1 (T1 < T10) -> latches
    //  DUT NBA: rdata=mem[addr], valid=1 committed at T10 (end of step)
    //
    //  Clocking block input sampling: fires at posedge+#1 = T10+1
    //  BUT SV LRM says clocking block inputs are sampled in the
    //  PREPONED region of the triggering edge - i.e., at T10 BEFORE
    //  any active events. So rd_cb samples rdata/valid at T10 seeing
    //  the OLD values (valid=0 from previous cycle). This is why
    //  valid is always 0 and data is shifted.
    //
    //  SOLUTION: bypass the clocking block for input sampling.
    //  After asserting re at @T0, wait for posedge T10 (when DUT
    //  latches), then wait #2 (past NBA region, into next delta),
    //  and sample vif.rdata / vif.valid directly from the interface.
    //  These raw signals reflect the committed NBA values.
    //
    //  Sequence:
    //    @rd_cb (T0):  assert re, addr
    //    @(posedge clk) (T10): DUT latches; wait past NBA
    //    #2: sample vif.rdata, vif.valid (committed NBA values)
    //    deassert re (wire goes low before T20 posedge)
    //    @rd_cb (T20): idle, let pipeline clear
    // -------------------------------------------------------
    task drive(ram_transaction txn);
        // Step 1: assert re + addr (output #1 -> wire at T+1)
        @(vif.rd_cb);
        vif.rd_cb.re   <= 1'b1;
        vif.rd_cb.addr <= txn.addr;

        // Step 2: wait for the posedge where DUT latches re=1
        @(posedge vif.clk);
        // Wait past the NBA region so rdata/valid are committed
        #2;
        txn.rdata = vif.rdata;
        txn.valid = vif.valid;

        // Deassert re - wire goes low well before next posedge
        vif.rd_cb.re   <= 1'b0;
        vif.rd_cb.addr <= 7'h00;

        // Step 3: idle cycle - DUT clears valid, bus clean
        @(vif.rd_cb);

        $display("[RD-DRV] addr=0x%02h rdata=0x%02h valid=%0b",
                 txn.addr, txn.rdata, txn.valid);

        rd_done_mbx.put(txn);
    endtask

endclass : ram_read_driver

`endif // RAM_READ_DRIVER_SV
