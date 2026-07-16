`timescale 1ns/1ps
// ============================================================
// ram_if.sv
// Interface for 128x8 decoder-based RAM DUT
// ============================================================

interface ram_if (input logic clk);

    logic        rst_n  = 1'b0;
    logic        we     = 1'b0;
    logic        re     = 1'b0;
    logic [6:0]  addr   = 7'h00;
    logic [7:0]  wdata  = 8'h00;
    logic [7:0]  rdata;
    logic        valid;

    // -------------------------------------------------------
    // Write driver clocking block
    // -------------------------------------------------------
    clocking wr_cb @(posedge clk);
        default input #1 output #1;
        output rst_n;
        output we;
        output addr;
        output wdata;
        input  rdata;
        input  valid;
    endclocking

    // -------------------------------------------------------
    // Read driver clocking block
    // -------------------------------------------------------
    clocking rd_cb @(posedge clk);
        default input #1 output #1;
        output re;
        output addr;
        input  rdata;
        input  valid;
    endclocking

    // -------------------------------------------------------
    // Monitor clocking block
    // -------------------------------------------------------
    clocking mon_cb @(posedge clk);
        default input #1;
        input rst_n;
        input we;
        input re;
        input addr;
        input wdata;
        input rdata;
        input valid;
    endclocking

    // -------------------------------------------------------
    // Modports - READ_DRV exposes both clocking block AND
    // raw signals so the driver can sample rdata/valid
    // outside the clocking block (avoiding preponed sampling)
    // -------------------------------------------------------
    modport WRITE_DRV (clocking wr_cb, input clk);
    modport READ_DRV  (clocking rd_cb, input clk, input rdata, input valid);
    modport WR_MON    (clocking mon_cb, input clk);
    modport RD_MON    (clocking mon_cb, input clk);

endinterface : ram_if
