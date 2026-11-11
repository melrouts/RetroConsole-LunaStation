create_clock -name sys_clk -period 37.037 [get_ports {clk}]
create_clock -name pixel_clk -period 39.682540 [get_nets {core.blue_encoder.clk}]
create_clock -name serial_clk -period 7.936508 [get_nets {core.output_stage.serial_clk}]
