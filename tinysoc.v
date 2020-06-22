module tinysoc
  #(parameter clk_freq_hz = 0)
   (input  clk,
    output reg q = 1'b0);

   reg [$clog2(clk_freq_hz)-1:0] count = 0;

   always @(posedge clk) begin
      count <= count + 1;
      if (count == clk_freq_hz-1) begin
         q <= !q;
         count <= 0;
      end
   end
endmodule

// Connects tinysoc to the TinyFPGA hardware
module hardware
   (
      // 16MHz clock
      input CLK,
      // User LED
      output LED,
      
      // USB Interface
      output USBPU,
      output USBP,
      output USBN);

   // Disable USB interface
   assign USBPU = 1'b1;
   assign USBP = 1'b0;
   assign USBN = 1'b0;

   // Parameter comes from tinysoc.core
   parameter clk_freq_hz = 16_000_000;

   tinysoc
     #(.clk_freq_hz (clk_freq_hz))
   tinyfpga
     (.clk (CLK),
      .q   (LED));
endmodule