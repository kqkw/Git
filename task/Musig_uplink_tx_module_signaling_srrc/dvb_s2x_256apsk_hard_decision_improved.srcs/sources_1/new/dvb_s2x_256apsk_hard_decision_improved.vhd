----------------------------------------------------------------------------------
-- Company: 
-- Engineer:  
-- 
-- Create Date: 
-- Design Name: 
-- Module Name: Musig_uplink_tx_module_signaling_srrc_parallel 
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 高吞吐率并行SRRC滤波器 - 所有乘法运算并行执行
-- 
-- Dependencies: 
-- 
-- Revision:
-- Additional Comments:
-- 采用并行乘法累加结构，所有15个乘法运算同时进行
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;
use IEEE.NUMERIC_STD.all;

entity Musig_uplink_tx_module_signaling_srrc_parallel is
   generic (
        W_in           :     integer := 12;  -- Input bit width   
        W_filter       :     integer := 16;  -- Filter width
        L_filter       :     integer := 15;  -- Filter length 
        L_multOut      :     integer := 18   -- 乘法器输出位宽
    );
    Port ( 
        i_clk          :     in   std_logic;
        i_rst          :     in   std_logic;
        iv_data        :     in   std_logic_vector(W_in-1 downto 0);    -- 输入数据总线
        i_en           :     in   std_logic;    -- 输入使能信号
       
        ov_data        :     out  std_logic_vector(W_in-1 downto 0);    -- 输出数据总线
        o_data_en      :     out  std_logic     -- 输出数据有效信号
    );
end Musig_uplink_tx_module_signaling_srrc_parallel;

architecture Behavioral of Musig_uplink_tx_module_signaling_srrc_parallel is

    -- 数据类型定义
    type ARRAY12 is array (NATURAL RANGE <>) of std_logic_vector(W_in - 1 downto 0);
    type ARRAY16 is array (NATURAL RANGE <>) of std_logic_vector(W_filter - 1 downto 0);
    type ARRAY18 is array (NATURAL RANGE <>) of std_logic_vector(L_multOut - 1 downto 0);
    
    -- 滤波器系数 
    constant filter_coef : ARRAY16(L_filter-1 downto 0) := (
        x"007F",x"FD99",x"FAFA",x"FC9A",x"0506",x"1288",x"1F36",x"2467",
        x"1F36",x"1288",x"0506",x"FC9A",x"FAFA",x"FD99",x"007F"
    );

    -- 信号定义
    signal sym_reg               : ARRAY12(L_filter - 1 downto 0);  -- 移位寄存器
    signal mult_results          : ARRAY18(L_filter - 1 downto 0);  -- 并行乘法结果
    signal insert_zero_en        : std_logic;   
    signal insert_zero_data      : std_logic_vector(W_in-1 downto 0);   
    signal en_tmp                : std_logic;  
    signal en_d1                 : std_logic;   
    signal en_tmp1               : std_logic; 
    
    -- 插零控制相关信号
    signal cnt_tmp4              : std_logic_vector(7 downto 0); 
    signal insert_entet          : std_logic;    
    signal sym_regen             : std_logic;   
    signal sym_regen_d1          : std_logic;    
    signal sym_regen_d2          : std_logic;
    
    -- 并行累加相关信号
    signal sum_stage1            : ARRAY18(7 downto 0);   -- 第一级累加结果 (8个)
    signal sum_stage2            : ARRAY18(3 downto 0);   -- 第二级累加结果 (4个)
    signal sum_stage3            : ARRAY18(1 downto 0);   -- 第三级累加结果 (2个)
    signal sum_final             : std_logic_vector(L_multOut downto 0);  -- 最终累加结果
    
    signal ovtmpdata             : std_logic_vector(11 downto 0);
    signal otmpen                : std_logic;
    
    -- 流水线控制信号
    signal valid_stage1          : std_logic;
    signal valid_stage2          : std_logic;
    signal valid_stage3          : std_logic;
    signal valid_final           : std_logic;

begin

    -- 使能控制逻辑 
    entmp1 : process(i_clk,i_rst)
    begin
        if i_rst = '1' then
              en_tmp1 <= '0';
        elsif (i_clk='1' and i_clk'event) then
            if(i_en='1')then
              en_tmp1 <= '1';
            end if;
        end if;
    end process;

    entmp_delay : process(i_clk,i_rst)
    begin
        if i_rst = '1' then
             en_d1 <= '0';
             sym_regen <= '0';
             sym_regen_d1 <= '0';
             sym_regen_d2 <= '0';
        elsif (i_clk='1' and i_clk'event) then
             en_d1 <= i_en;
             sym_regen <= insert_zero_en;
             sym_regen_d1 <= sym_regen;
             sym_regen_d2 <= sym_regen_d1;
        end if;
    end process;

    -- 插零时序控制 
    process(i_clk,i_rst)
    begin
         if(i_rst='1')then
            cnt_tmp4 <= (others=>'0');
         elsif(i_clk'event and i_clk='1')then
            if(i_en = '1' and en_d1 ='0') then
                cnt_tmp4 <= "00000001";
            elsif(cnt_tmp4 >0)then
                 if(cnt_tmp4=63)then
                    cnt_tmp4 <= "00000000";
                 else
                    cnt_tmp4 <= cnt_tmp4 + "00000001";
                 end if;
            end if;
         end if;
    end process;

    process(i_clk,i_rst)
    begin
         if(i_rst='1')then
            insert_entet <= '0';
         elsif(i_clk'event and i_clk='1')then
            if(cnt_tmp4=15 or cnt_tmp4=31 or cnt_tmp4=47 or cnt_tmp4=63 )then
                insert_entet <= '1';
            else
                insert_entet <= '0';
            end if;
         end if;
    end process;

    insert_gen : process(i_clk,i_rst)
    begin
        if i_rst = '1' then
            insert_zero_en <= '0';
            insert_zero_data <= (others => '0');
        elsif (i_clk='1' and i_clk'event) then
            insert_zero_en <= insert_entet or i_en;
            insert_zero_data <= iv_data;
        end if;
    end process;

    -- 移位寄存器 
    data_flow: process(i_rst,i_clk)
    begin
        if(i_clk'event and i_clk = '1')then
            if(i_rst = '1') then
                sym_reg <= (others=>(others=>'0'));        
            elsif(insert_zero_en= '1') then
                for i in 0 to L_filter-2 loop
                    sym_reg(i+1) <= sym_reg(i);
                end loop;
                sym_reg(0) <= insert_zero_data;
            else
                sym_reg<=sym_reg;
            end if;    
        end if;
    end process;

    -- 并行乘法运算 
    parallel_mult: process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            mult_results <= (others => (others => '0'));
            valid_stage1 <= '0';
        elsif (i_clk'event and i_clk='1') then
            valid_stage1 <= insert_zero_en;  -- 传递有效信号
            
            -- 所有15个乘法运算并行执行
            for i in 0 to L_filter-1 loop
                if(sym_reg(i) /= 0 and sym_reg(i)(11) = '1') then
                    -- 负数情况
                    mult_results(i) <= sxt(0-filter_coef(i), L_multOut);  
                elsif(sym_reg(i) /= 0 and sym_reg(i)(11) = '0') then
                    -- 正数情况
                    mult_results(i) <= sxt(filter_coef(i), L_multOut);
                else
                    -- 零值情况
                    mult_results(i) <= (others=>'0');
                end if;
            end loop;              
        end if;
    end process;

    -- 三级流水线并行累加树   15-8-4-2-1
    -- 第一级：15个数据分成8组进行两两累加
    stage1_add: process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            sum_stage1 <= (others => (others => '0'));
            valid_stage2 <= '0';
        elsif (i_clk'event and i_clk='1') then
            valid_stage2 <= valid_stage1;
            
            -- 前14个数据两两相加
            for i in 0 to 6 loop
                sum_stage1(i) <= sxt(mult_results(2*i), L_multOut+1) + 
                                sxt(mult_results(2*i+1), L_multOut+1);
            end loop;
            -- 最后一个数据单独处理
            sum_stage1(7) <= sxt(mult_results(14), L_multOut+1);
        end if;
    end process;

    -- 第二级：8个数据分成4组进行累加
    stage2_add: process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            sum_stage2 <= (others => (others => '0'));
            valid_stage3 <= '0';
        elsif (i_clk'event and i_clk='1') then
            valid_stage3 <= valid_stage2;
            
            -- 前6个数据三三相加
            for i in 0 to 2 loop
                sum_stage2(i) <= sxt(sum_stage1(2*i), L_multOut+1) + 
                                sxt(sum_stage1(2*i+1), L_multOut+1);
            end loop;
            -- 最后两个数据相加
            sum_stage2(3) <= sxt(sum_stage1(6), L_multOut+1) + 
                            sxt(sum_stage1(7), L_multOut+1);
        end if;
    end process;

    -- 第三级：4个数据最终累加
    stage3_add: process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            sum_stage3 <= (others => (others => '0'));
            valid_final <= '0';
        elsif (i_clk'event and i_clk='1') then
            valid_final <= valid_stage3;
            
            sum_stage3(0) <= sxt(sum_stage2(0), L_multOut+1) + 
                            sxt(sum_stage2(1), L_multOut+1);
            sum_stage3(1) <= sxt(sum_stage2(2), L_multOut+1) + 
                            sxt(sum_stage2(3), L_multOut+1);
        end if;
    end process;

    -- 最终级：得到最终结果
    final_add: process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            sum_final <= (others => '0');
        elsif (i_clk'event and i_clk='1') then
            sum_final <= sxt(sum_stage3(0), L_multOut+2) + 
                        sxt(sum_stage3(1), L_multOut+2);
        end if;
    end process;

    -- 输出处理 
    out_gen:process(i_clk,i_rst) 
    begin
        if(i_rst='1')then
            ovtmpdata<=(others=>'0');
            otmpen <= '0';
        elsif(i_clk'event and i_clk='1' )then
            otmpen <= valid_final;
            -- 保持原有的截位和舍入逻辑
            ovtmpdata <= sum_final(17 downto 6) + (not(sum_final(17)) and sum_final(5)); 
        end if;
    end process;

    -- 最终输出
    process(i_clk,i_rst)
    begin
          if(i_rst='1')then
              o_data_en<='0';
              ov_data<=(others=>'0');
          elsif(i_clk'event and i_clk='1')then
              ov_data <= ovtmpdata(10 downto 0) & '0';
              ov_data(11) <= ovtmpdata(11);
              o_data_en <= otmpen;
           end if;
    end process;

end Behavioral;