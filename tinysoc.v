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

   // Parameter comes from tinysoc.core
   parameter clk_freq_hz = 16_000_000;

   // Add tinysoc module (which just blinks the LED for now)
   tinysoc
     #(.clk_freq_hz (clk_freq_hz))
   tinyfpga
     (.clk (CLK),
      .q   (LED));
   
   wire clk_48mhz;

   wire clk_locked;

   // Use an icepll generated pll
   pll pll48( .clock_in(CLK), .clock_out(clk_48mhz), .locked( clk_locked ) );

   // Generate reset signal
   reg [5:0] reset_cnt = 0;
   wire reset = ~reset_cnt[5];
   always @(posedge clk_48mhz)
      if ( clk_locked )
         reset_cnt <= reset_cnt + reset;

   // uart pipeline in
   wire [7:0] uart_in_data;
   wire       uart_in_valid;
   wire       uart_in_ready;
   
   wire usb_p_tx;
   wire usb_n_tx;
   wire usb_p_rx;
   wire usb_n_rx;
   wire usb_tx_en;

   // usb uart - this instanciates the entire USB device.
   usb_uart uart (
      .clk_48mhz  (clk_48mhz),
      .reset      (reset),

      // pins
      .USBP( USBP ),
      .USBN( USBN ),

      // uart pipeline in
      .uart_in_data( uart_in_data ),
      .uart_in_valid( uart_in_valid ),
      .uart_in_ready( uart_in_ready ),

      .uart_out_data( uart_in_data ),
      .uart_out_valid( uart_in_valid ),
      .uart_out_ready( uart_in_ready  )

      //.debug( debug )
   );

   // USB Host Detect Pull Up
   assign USBPU = 1'b1;
endmodule