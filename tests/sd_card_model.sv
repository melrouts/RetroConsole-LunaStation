`timescale 1ns/1ps
module sd_card_model (
    input wire sck,
    input wire cs_n,
    input wire mosi,
    output reg miso = 1
);
    reg [7:0] card [0:131071];
    reg [7:0] queue [0:599];
    integer head = 0;
    integer tail = 0;
    integer bit_count = 0;
    integer command_count = 0;
    reg [7:0] incoming = 0;
    reg [7:0] outgoing = 8'hff;
    reg [5:0] command_index;
    reg [31:0] argument;
    reg boundary = 0;
    reg idle = 1;
    reg app_command = 0;
    integer write_stage = 0, write_index = 0;
    reg [31:0] write_lba;
    reg [15:0] write_crc, received_crc;
    reg [7:0] write_buffer [0:511];
    integer writes = 0;
    initial begin
        if ($test$plusargs("game") && $test$plusargs("bad-crc"))
            $readmemh("build/game-card-bad.hex", card);
        else if ($test$plusargs("game"))
            $readmemh("build/game-card.hex", card);
        else if ($test$plusargs("bad-crc"))
            $readmemh("build/test-card-bad.hex", card);
        else
            $readmemh("build/test-card.hex", card);
    end
    task automatic put(input reg [7:0] value);
        if (tail >= 600) $fatal(1, "SD response queue overflow");
        queue[tail] = value;
        tail = tail + 1;
    endtask
    task automatic execute_command;
        reg [15:0] crc;
        reg [7:0] value;
        case (command_index)
            0: begin
                idle = 1;
                put(1);
            end
            8: begin
                if (argument != 32'h1aa) $fatal(1, "Bad CMD8 argument");
                put(1); put(0); put(0); put(1); put(8'haa);
            end
            55: begin
                app_command = 1;
                put({7'b0, idle});
            end
            41: begin
                if (!app_command || argument != 32'h40000000)
                    $fatal(1, "Expected SDHC ACMD41");
                idle = 0; app_command = 0;
                put(0);
            end
            58: begin
                put(0); put(8'hc0); put(8'hff); put(8'h80); put(0);
            end
            17: begin
                if (idle || argument >= 256) $fatal(1, "Invalid SDHC block address %0d", argument);
                put(0); put(8'hff); put(8'hfe);
                crc = 0;
                for (integer i = 0; i < 512; i = i + 1) begin
                    value = card[argument*512 + 32'(i)];
                    put(value);
                    crc = crc ^ {value, 8'b0};
                    for (integer bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                        crc = (crc << 1) ^ (crc[15] ? 16'h1021 : 16'b0);
                end
                put(crc[15:8]); put(crc[7:0]);
            end
            24: begin
                if (idle || !((argument >= 85 && argument < 101) ||
                              (argument >= 117 && argument < 133)))
                    $fatal(1, "Write outside preallocated update slot: %0d", argument);
                write_lba = argument;
                write_stage = 1;
                put(0);
            end
            default: $fatal(1, "Unexpected SD command %0d", command_index);
        endcase
    endtask
    always @(posedge cs_n) begin
        head = 0; tail = 0;
        bit_count = 0; command_count = 0;
        outgoing = 8'hff; miso = 1; boundary = 0;
        write_stage = 0;
    end
    always @(posedge sck) begin
        if (!cs_n) begin
            incoming = {incoming[6:0], mosi};
            if (bit_count == 7) begin
                boundary = 1;
                bit_count = 0;
                if (write_stage == 1) begin
                    if (incoming == 8'hfe) begin
                        write_stage = 2; write_index = 0; write_crc = 0;
                    end
                end else if (write_stage == 2) begin
                    write_buffer[write_index] = incoming;
                    write_crc = write_crc ^ {incoming, 8'b0};
                    for (integer b = 0; b < 8; b = b + 1)
                        write_crc = (write_crc << 1) ^ (write_crc[15] ? 16'h1021 : 16'b0);
                    write_index = write_index + 1;
                    if (write_index == 512) write_stage = 3;
                end else if (write_stage == 3) begin
                    received_crc = {incoming, 8'b0}; write_stage = 4;
                end else if (write_stage == 4) begin
                    received_crc = received_crc | {8'b0, incoming};
                    if (received_crc != write_crc) $fatal(1, "CMD24 CRC16 mismatch");
                    write_stage = 0;
                    if ($test$plusargs("write-reject")) begin
                        put(8'h0d);
                    end else begin
                        for (integer i = 0; i < 512; i = i + 1)
                            card[write_lba*512 + 32'(i)] = write_buffer[i];
                        writes = writes + 1;
                        put(8'h05); put(0); put(0); put(0); put(8'hff);
                    end
                end else if (command_count == 0) begin
                    if (incoming[7:6] == 2'b01) begin
                        command_index = incoming[5:0];
                        command_count = 1;
                        argument = 0;
                    end
                end else if (command_count < 5) begin
                    argument = {argument[23:0], incoming};
                    command_count = command_count + 1;
                end else begin
                    command_count = 0;
                    execute_command();
                end
            end else begin
                bit_count = bit_count + 1;
            end
        end
    end
    always @(negedge sck) begin
        if (!cs_n) begin
            if (boundary) begin
                if (head < tail) begin
                    outgoing = queue[head];
                    head = head + 1;
                end else begin
                    outgoing = 8'hff;
                end
                boundary = 0;
            end
            miso = outgoing[7];
            outgoing = {outgoing[6:0], 1'b1};
        end
    end
endmodule
