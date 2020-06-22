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
      
      // hardware UART
      output PIN_TX,
      input PIN_RX,

      // onboard SPI flash interface
      output SPI_SS,
      output SPI_SCK,
      inout  SPI_IO0,
      inout  SPI_IO1,
      inout  SPI_IO2,
      inout  SPI_IO3,

      // User LED
      output LED,
      
      // USB Interface
      output USBPU,
      output USBP,
      output USBN);

   // USB Host Detect Pull Up
   assign USBPU = 1'b1;

   // Parameter comes from tinysoc.core
   parameter clk_freq_hz = 16_000_000;

   // Add tinysoc module (which just blinks the LED for now)
   // tinysoc
   //   #(.clk_freq_hz (clk_freq_hz))
   // tinyfpga
   //   (.clk (CLK),
   //    .q   (LED));
   
   wire clk_48mhz;
   wire clk_locked;

   // Use an icepll generated pll
   pll pll48( .clock_in(CLK), .clock_out(clk_48mhz), .locked( clk_locked ) );

   ///////////////////////////////////
   // Power-on Reset
   // Only begins to reset after the
   // 48MHz PLL is locked.
   ///////////////////////////////////
   reg [5:0] reset_cnt = 0;
   wire resetn = &reset_cnt;
   wire reset = ~reset_cnt[5];

   always @(posedge CLK) begin
      if ( clk_locked )
         reset_cnt <= reset_cnt + !resetn;
   end

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
      .pin_usb_p( USBP ),
      .pin_usb_n( USBN ),

      // uart pipeline in
      .uart_in_data( uart_in_data ),
      .uart_in_valid( uart_in_valid ),
      .uart_in_ready( uart_in_ready ),

      .uart_out_data( uart_in_data ),
      .uart_out_valid( uart_in_valid ),
      .uart_out_ready( uart_in_ready  )

      //.debug( debug )
   );

   // Clock wire for picosoc
   wire clk = clk_16mhz;

   ///////////////////////////////////
   // SPI Flash Interface
   ///////////////////////////////////
   wire flash_io0_oe, flash_io0_do, flash_io0_di;
   wire flash_io1_oe, flash_io1_do, flash_io1_di;
   wire flash_io2_oe, flash_io2_do, flash_io2_di;
   wire flash_io3_oe, flash_io3_do, flash_io3_di;

   SB_IO #(
      .PIN_TYPE(6'b 1010_01),
      .PULLUP(1'b 0)
   ) flash_io_buf [3:0] (
      .PACKAGE_PIN({SPI_IO3, SPI_IO2, SPI_IO1, SPI_IO0}),
      .OUTPUT_ENABLE({flash_io3_oe, flash_io2_oe, flash_io1_oe, flash_io0_oe}),
      .D_OUT_0({flash_io3_do, flash_io2_do, flash_io1_do, flash_io0_do}),
      .D_IN_0({flash_io3_di, flash_io2_di, flash_io1_di, flash_io0_di})
   );

   ///////////////////////////////////
   // Peripheral Bus
   ///////////////////////////////////
   wire        iomem_valid;
   reg         iomem_ready;
   wire [3:0]  iomem_wstrb;
   wire [31:0] iomem_addr;
   wire [31:0] iomem_wdata;
   reg  [31:0] iomem_rdata;

   reg [31:0] gpio;
   assign LED = gpio[0];

   always @(posedge clk) begin
      if (!resetn) begin
         gpio <= 0;
      end else begin
         iomem_ready <= 0;

         ///////////////////////////
         // GPIO Peripheral
         ///////////////////////////
         if (iomem_valid && !iomem_ready && iomem_addr[31:24] == 8'h03) begin
               iomem_ready <= 1;
               iomem_rdata <= gpio;
               if (iomem_wstrb[0]) gpio[ 7: 0] <= iomem_wdata[ 7: 0];
               if (iomem_wstrb[1]) gpio[15: 8] <= iomem_wdata[15: 8];
               if (iomem_wstrb[2]) gpio[23:16] <= iomem_wdata[23:16];
               if (iomem_wstrb[3]) gpio[31:24] <= iomem_wdata[31:24];
         end

         
         ///////////////////////////
         // Template Peripheral
         ///////////////////////////
         if (iomem_valid && !iomem_ready && iomem_addr[31:24] == 8'h04) begin
               iomem_ready <= 1;
               iomem_rdata <= 32'h0;
         end
      end
   end

   picosoc #(
      .PROGADDR_RESET(32'h0005_0000), // beginning of user space in SPI flash
      .PROGADDR_IRQ(32'h0005_0010),
      .MEM_WORDS(2048)                // use 2KBytes of block RAM by default
   ) soc (
      .clk          (clk         ),
      .resetn       (resetn      ),

      .ser_tx       (PIN_TX       ),
      .ser_rx       (PIN_RX       ),

      .flash_csb    (SPI_SS   ),
      .flash_clk    (SPI_CLK   ),

      .flash_io0_oe (flash_io0_oe),
      .flash_io1_oe (flash_io1_oe),
      .flash_io2_oe (flash_io2_oe),
      .flash_io3_oe (flash_io3_oe),

      .flash_io0_do (flash_io0_do),
      .flash_io1_do (flash_io1_do),
      .flash_io2_do (flash_io2_do),
      .flash_io3_do (flash_io3_do),

      .flash_io0_di (flash_io0_di),
      .flash_io1_di (flash_io1_di),
      .flash_io2_di (flash_io2_di),
      .flash_io3_di (flash_io3_di),

      .irq_5        (1'b0        ),
      .irq_6        (1'b0        ),
      .irq_7        (1'b0        ),

      .iomem_valid  (iomem_valid ),
      .iomem_ready  (iomem_ready ),
      .iomem_wstrb  (iomem_wstrb ),
      .iomem_addr   (iomem_addr  ),
      .iomem_wdata  (iomem_wdata ),
      .iomem_rdata  (iomem_rdata )
   );
endmodule