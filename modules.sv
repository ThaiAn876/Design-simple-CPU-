module D_FF(
	input logic D,clk,
	output logic Q);
always_ff @(posedge clk)
	begin 
		Q<=D;
	end
endmodule
module register9bit(
    input  logic        clk,
    input  logic        in,        
    input  logic [8:0]  D_in,      
    output logic [8:0]  Q_out      
);

    logic [8:0] D_mux; 
    assign D_mux = in ? D_in : Q_out;

    genvar i;
    generate 
        for(i=0; i<9; i++) begin : reg9
            D_FF dff_inst(
                .D  (D_mux[i]),
                .clk(clk),
                .Q  (Q_out[i])
            );
        end
    endgenerate

endmodule
module proc (
    input logic [8:0] DIN,
    input logic Resetn, Clock, Run,
    output logic Done,
    output logic [8:0] BusWires
);

    // Khai báo các biến (declare variables)
    logic [8:0] R [0:7], IR, A, G; 
    logic Ain, Gin, IRin;
    logic [7:0] R_in; 
    logic [7:0] R_out; 
    logic G_out, DIN_out;
    logic AddSub_ctrl;
    logic [8:0] AddSub_out; 

    // FSM State Register
    typedef enum {T0, T1, T2, T3} states; 
    logic [1:0] Tstep_Q, Tstep_D; 

    // Tín hiệu giải mã từ IR
    logic [2:0] I; 
    logic [7:0] Xreg, Yreg; 
    
    // Biến lặp cho khối generate (genvar)
    genvar i; 
    
    // Biến lặp cho khối always_comb (int)
    int j; 

    // 1. Decoder Inputs và Opcode
    // Lỗi 10199 đã được sửa: Đảo ngược hướng truy cập bit (từ lớn đến nhỏ)
    // Cấu trúc: [8:0]. Giả định YYY(IR[8:6]), XXX(IR[5:3]), III(IR[2:0])
    assign I = IR[2:0]; // III (Opcode)
    
    // SỬA LỖI 10149: Thêm tên thể hiện (u_decX, u_decY) để tránh khai báo lại
    // Decoders (XXX)
    dec3to8 u_decX (
        .W(IR[5:3]), 
        .En(1'b1), 
        .Y(Xreg)
    ); 
    // Decoders (YYY)
    dec3to8 u_decY (
        .W(IR[8:6]), 
        .En(1'b1), 
        .Y(Yreg)
    ); 

    // 2. Add/Sub Unit
    AddSubUnit u_addsub (
        .A_in(A), 
        .Bus_in(BusWires), 
        .AddSub(AddSub_ctrl), 
        .AddSub_out(AddSub_out)
    );

    // 3. FSM State Register (Control FSM flip-flops)
    always_ff @(posedge Clock, negedge Resetn) begin
        if (!Resetn)
            Tstep_Q <= T0; 
        else
            Tstep_Q <= Tstep_D;
    end

    // 4. Các Thanh ghi (Registers)
    regn #(9) u_IR (.R(DIN), .Rin(IRin), .Clock(Clock), .Q(IR));
    regn #(9) u_A (.R(BusWires), .Rin(Ain), .Clock(Clock), .Q(A));
    regn #(9) u_G (.R(AddSub_out), .Rin(Gin), .Clock(Clock), .Q(G));

    // Thanh ghi R0 - R7
    generate 
        for (i=0; i<8; i++) begin : R_REGS
            regn #(9) u_R (
                .R(BusWires), 
                .Rin(R_in[i]), 
                .Clock(Clock), 
                .Q(R[i])
            );
        end
    endgenerate

    // 5. Định nghĩa Bus (Bus definition)
    always_comb begin
        BusWires = 9'b000000000;
        
        // Sử dụng biến 'j' (int)
        
        if (DIN_out)
            BusWires = DIN;

        if (G_out)
            BusWires = G;

        for (j=0; j<8; j++) begin
            if (R_out[j]) begin
                BusWires = R[j];
            end
        end
    end

    // 6. FSM Next State Logic (Control FSM state table)
    always_comb begin
        Tstep_D = Tstep_Q; 

        case (Tstep_Q)
            T0: 
                if (!Run) Tstep_D = T0;
                else Tstep_D = T1;

            T1: 
                case (I)
                    3'b000: Tstep_D = T0; 
                    3'b001: Tstep_D = T0; 
                    3'b010: Tstep_D = T2; 
                    3'b011: Tstep_D = T2;
default: Tstep_D = T0;
                endcase

            T2: 
                Tstep_D = T3;

            T3: 
                Tstep_D = T0;

            default: Tstep_D = T0;
        endcase
    end

    // 7. FSM Output Logic (Control FSM outputs)
    always_comb begin
        // Specify initial values
        IRin = 1'b0;
        Ain = 1'b0;
        Gin = 1'b0;
        R_in = 8'b00000000; 
        R_out = 8'b00000000; 
        G_out = 1'b0;
        DIN_out = 1'b0;
        AddSub_ctrl = 1'b0; 
        Done = 1'b0;

        case (Tstep_Q)
            T0: // store DIN in IR in time step 0
                IRin = 1'b1;

            T1: 
                case (I)
                    // (mv) I0: RYout, RXin, Done
                    3'b000: begin 
                        R_out = Yreg; 
                        R_in = Xreg; 
                        Done = 1'b1;
                    end
                    // (mvi) I1: DINout, RXin, Done
                    3'b001: begin 
                        DIN_out = 1'b1;
                        R_in = Xreg;
                        Done = 1'b1;
                    end
                    // (add) I2: RXout, Ain
                    3'b010: begin 
                        R_out = Xreg;
                        Ain = 1'b1;
                    end
                    // (sub) I3: RXout, Ain
                    3'b011: begin 
                        R_out = Xreg;
                        Ain = 1'b1;
                    end
                    default: ; 
                endcase

            T2: 
                case (I)
                    // (add) I2: RYout, Gin
                    3'b010: begin 
                        R_out = Yreg;
                        Gin = 1'b1;
                        AddSub_ctrl = 1'b0; // Add
                    end
                    // (sub) I3: RYout, Gin, AddSub
                    3'b011: begin 
                        R_out = Yreg;
                        Gin = 1'b1;
                        AddSub_ctrl = 1'b1; // Sub
                    end
                    default: ; 
                endcase

            T3: 
                case (I)
                    // (add) I2: Gout, RXin, Done
                    3'b010: begin
                        G_out = 1'b1;
                        R_in = Xreg;
                        Done = 1'b1;
                    end
                    // (sub) I3: Gout, RXin, Done
                    3'b011: begin
                        G_out = 1'b1;
                        R_in = Xreg;
                        Done = 1'b1;
                    end
                    default: ; 
                endcase
            
            default: ; 
        endcase
    end

endmodule // proc