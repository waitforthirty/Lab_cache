`timescale 1ns / 1ps

module CacheController(
    rst,
    clk,

    wr,//Cache operation request signal
    rd,//Cache operation request signal

    data_rd,//Data returned from cache (Cache to host)
    data_wr,//Data written to cache (Host to cache)
    addr_req,// Cache request address (Host to cache)
    addr_resp,/*The data address of cache response (Cache to host, cache controller
                keeps the address of cache request in a buffer when cache miss happens)*/
    rdy,//Cache ready
    busy,//Cache busy

    wr_mem,//Memory operation request signals
    rd_mem,
    busy_mem,//Memory busy

    data_rd_mem,//Data returned from memory (Memory to cache)
    data_wr_mem,//Data written to memory (Cache to memory)
    addr_mem, //Memory access address (Cache to memory)

    cache_miss_count,//Cache miss statistics
    cache_hit_count  //Cache hit statistics
    );

    input  rst;// Reset
    input  clk;// System clk

    input  wr;
    input  rd;
    output [31:0] data_rd;
    reg    [31:0] data_rd;

    input  [31:0] data_wr;
    input  [31:0] addr_req;
    output [31:0] addr_resp;
    reg    [31:0] addr_resp;
    output rdy;
    reg    rdy;
    output busy;
    reg    busy;

    output  wr_mem;
    reg     wr_mem;
    output  rd_mem;
    reg     rd_mem;
    input   busy_mem;
    input  [31:0] data_rd_mem;
    output [31:0] data_wr_mem;
    reg    [31:0] data_wr_mem;
    output [31:0] addr_mem;
    reg    [31:0] addr_mem;

    output [31:0] cache_miss_count;
    reg    [31:0] cache_miss_count;
    output [31:0] cache_hit_count;
    reg    [31:0] cache_hit_count;


    reg [15:0]  cache_valid; //Valid Flag
    reg [15:0]  cache_dirty;  //Dirty Flag
    reg [23:0]  cache_tag [15:0];//the number of cache lines is 16
    reg [127:0] cache_data[15:0];//every cache line is 16B=128b,total capacity of cache is 256B = 16*16

    reg [1:0]   cache_count = 2'h0;

    wire [23:0] addr_tag = addr_req[31:8];
    wire [3:0]  addr_index = addr_req[7:4];
    wire [3:0]  addr_offset = addr_req[3:0];
    
    reg [31:0] iCache_data_wr;
    reg mem_done;
    reg hit,dirty,miss,valid;

    reg  rd_temp = 1'b1;
  
    reg[3:0] mem_data_cnt = 4'h0;
    

    localparam [4:0] /* synopsys enum state_info */
            IDLE = 5'b00001,
            TAG_Check =5'b00010,
            EVICT = 5'b00100,
            REFILL = 5'b01000,
            Cache_OP = 5'b10000;   

    reg [4:0]     /* synopsys enum state_info */ state;
    reg [4:0]     /* synopsys enum state_info */ next_state;
   
   /*AUTOASCIIENUM("state","state_asc","SM_")*/   
   // Beginning of automatic ASCII enum decoding
    reg [71:0]    state_asc;              // Decode of state
    always @(state) begin
      case ({state})
        IDLE:      state_asc = "idle     ";
        TAG_Check: state_asc = "tag_check";
        EVICT:     state_asc = "evict    ";
        REFILL:    state_asc = "refill   ";
        Cache_OP:  state_asc = "cache_op ";
        default:      state_asc = "%Error   ";
      endcase
    end
   // End of automatics
   /*AUTOASCIIENUM("next_state","nstate_asc","SM_")*/
   // Beginning of automatic ASCII enum decoding
    reg [71:0]           nstate_asc;             // Decode of next_state
    always @(next_state) begin
      case ({next_state})
        IDLE:      nstate_asc = "idle     ";
        TAG_Check: nstate_asc = "tag_check";
        EVICT:     nstate_asc = "evict    ";
        REFILL:    nstate_asc = "refill   ";
        Cache_OP:  nstate_asc = "cache_op ";
        default:      nstate_asc = "%Error   ";
      endcase
    end
   // End of automatics
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // reset
            data_rd <= 32'hZZZZZZZZ;
            cache_count <= 2'h0;
            rd_mem <= 1'b0;
            wr_mem <= 1'b0;
            addr_mem <= 0;         
            rd_temp <= 1'b1;
            addr_resp <= 32'hZZZZZZZZ;
            cache_valid <= 16'h0000;
            cache_dirty <= 16'h0000;
            hit <= 1'b0;
            miss <= 1'b0;
            valid <= 1'b0;
            dirty <= 1'b0;
            mem_data_cnt <= 4'h0;
            state <= IDLE;
            			
        end
        else begin
            state <= next_state; 
        end
    end    
    
    always @(*) 
        case(state)
            IDLE: if (wr || rd) begin
                    next_state = TAG_Check;     
                end
            TAG_Check: 
                    if (valid && dirty && miss) begin
                        next_state = EVICT;
                    end  
                    else if(valid && hit) begin
                        next_state = Cache_OP;
                    end
                    else if ((!valid)||((!dirty)&&miss)) begin
                        next_state = REFILL;
                    end
            EVICT : if (mem_done) begin
                       next_state = REFILL;
                    end                    
            REFILL: if (mem_done) begin 
                        next_state = Cache_OP; 
                    end 
            Cache_OP:next_state = IDLE ;                    
            default:next_state = IDLE ;
        endcase     

//first of all set the I/O Controller registers' bits
//Then set I/O device's data registers

// judege the bits of hit, miss, valid, dirty which are prepared for the next state 

    always @(posedge clk or posedge rst) begin
if(rst)
begin
next_state <= IDLE;	
end else
            case(next_state)
                TAG_Check: 
                        if (wr || rd) begin
                            addr_resp <= addr_req;                        
                            iCache_data_wr <= data_wr;                        
                            rd_temp <= rd;    
                            hit <= (addr_tag == cache_tag[addr_index])? 1'b1 : 1'b0;                    
                            miss <= (addr_tag == cache_tag[addr_index])? 1'b0 : 1'b1;
                            valid <= cache_valid[addr_index];
                            dirty <= cache_dirty[addr_index]; 
                        end

                EVICT : 
                        if (!busy_mem) begin
                        addr_mem[31:8] <= cache_tag[addr_resp[7:4]];
                        addr_mem[ 7:4] <= addr_resp[7:4];
                        addr_mem[ 3:0] <= mem_data_cnt;
                        mem_data_cnt <= mem_data_cnt + 4;
                        wr_mem <= 1'b1;
                        rd_mem <= 1'b0;
                        case(mem_data_cnt[3:2])
                            2'b00:data_wr_mem <= cache_data[addr_resp[7:4]][31 : 0];
                            2'b01:data_wr_mem <= cache_data[addr_resp[7:4]][63 :32]; 
                            2'b10:data_wr_mem <= cache_data[addr_resp[7:4]][95 :64]; 
                            2'b11:data_wr_mem <= cache_data[addr_resp[7:4]][127:96];
                        endcase  
                    end   
                    else begin
                        addr_mem <= 0;
                        wr_mem <= 0;
                        rd_mem <= 0;                                                   
                   end                                                   
                REFILL :
                    if (!busy_mem) begin
                        addr_mem[31:4] <= addr_resp[31:4];
                        addr_mem[ 3:0] <= mem_data_cnt;
                        mem_data_cnt <= mem_data_cnt + 4;
                        cache_tag[addr_resp[7:4]] <= addr_resp[31:8];
                        cache_valid[addr_resp[7:4]] <= 1;
                        cache_dirty[addr_resp[7:4]] <= 0;
                        wr_mem <= 1'b0;
                        rd_mem <= 1'b1;
                            case(mem_data_cnt[3:2])
                                2'b00:cache_data[addr_resp[7:4]][31 :0 ] <= data_rd_mem;
                                2'b01:cache_data[addr_resp[7:4]][63 :32] <= data_rd_mem;
                                2'b10:cache_data[addr_resp[7:4]][95 :64] <= data_rd_mem;
                                2'b11:cache_data[addr_resp[7:4]][127:96] <= data_rd_mem;                                    
                            endcase 
                    end     else begin
                        addr_mem <= 0;
                        wr_mem <= 0;
                        rd_mem <= 0;                                                   
                   end   
                Cache_OP: if (rd_temp) begin
                            case(addr_resp[3:2])
                               2'h0: data_rd <= cache_data[addr_resp[7:4]][31:0];
                               2'h1: data_rd <= cache_data[addr_resp[7:4]][63:32]; 
                               2'h2: data_rd <= cache_data[addr_resp[7:4]][95:64]; 
                               2'h3: data_rd <= cache_data[addr_resp[7:4]][127:96];
                            endcase                   
                        end
                        else begin
                            cache_dirty[addr_resp[7:4]] <= 1'b1;
                            case(addr_resp[3:2])
                               2'h0: cache_data[addr_resp[7:4]][31:0]  <= iCache_data_wr;
                               2'h1: cache_data[addr_resp[7:4]][63:32] <= iCache_data_wr; 
                               2'h2: cache_data[addr_resp[7:4]][95:64] <= iCache_data_wr; 
                               2'h3: cache_data[addr_resp[7:4]][127:96] <= iCache_data_wr;
                            endcase
                        end                        
            endcase
       end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // reset
            busy <= 1'b1;
        end
        else if (next_state == IDLE ) begin
            busy <= 1'b0;
        end
        else begin
            busy <= 1'b1;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // reset
            rdy <= 1'b0;
        end
        else if (next_state == Cache_OP) begin
            rdy <= 1'b1;
        end
        else begin
            rdy <= 1'b0;
        end
    end
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // reset
           cache_hit_count <= 0;
        end
        else if (state == TAG_Check &&  hit) begin
            cache_hit_count <= cache_hit_count + 1'b1;
        end
        else begin
            cache_hit_count <= cache_hit_count;
        end
    end
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // reset
           cache_miss_count <= 0;        
        end
        else if (state == TAG_Check && miss) begin
           cache_miss_count <= cache_miss_count + 1'b1;
        end
        else begin
            cache_miss_count <= cache_miss_count;
        end
    end
    // always @(posedge clk or posedge rst) begin
    //      if (rst) begin
    //          // reset
    //         data_wr_mem <= 0; 
    //      end
    //      else if (next_state!=EVICT) begin
    //         data_wr_mem <= 0; 
    //      end
    //  end 
    always @(posedge clk or posedge rst) begin
	 if(rst)begin
	 mem_done <= 1;
	 end
	 else begin
       if (mem_data_cnt[3:2] == 2'b11) begin
            mem_done <= 1;     
        end
        else begin
            mem_done <= 0;
        end
     end
	 end    
endmodule