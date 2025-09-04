----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 2025/07/19
-- Design Name: DSP-based SRRC Filter
-- Module Name: Musig_uplink_tx_module_signaling_srrc_dsp - Behavioral
-- Project Name: 
-- Target Devices: XCVU13P-FHGB2104
-- Tool Versions: 
-- Description: DSP48E2-based implementation of 4x SRRC filter
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - DSP Implementation
-- Additional Comments:
-- 使用DSP48E2实现相同的SRRC滤波功能
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;
use IEEE.NUMERIC_STD.all;

-- Xilinx DSP库
library UNISIM;
use UNISIM.VComponents.all;

entity Musig_uplink_tx_module_signaling_srrc_dsp is
   generic (
        W_in           :     integer := 12;  -- 输入位宽   
        W_filter       :     integer := 16;  -- 滤波器系数位宽
        L_filter       :     integer := 15;  -- 滤波器长度 
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
end Musig_uplink_tx_module_signaling_srrc_dsp;

architecture Behavioral of Musig_uplink_tx_module_signaling_srrc_dsp is

    -- 数据类型定义
    type ARRAY12 is array (NATURAL RANGE <>) of std_logic_vector(W_in - 1 downto 0);
    type ARRAY16 is array (NATURAL RANGE <>) of std_logic_vector(W_filter - 1 downto 0);
    
    -- 滤波器系数 
    constant filter_coef : ARRAY16(14 downto 0) := (
        x"007F",x"FD99",x"FAFA",x"FC9A",x"0506",x"1288",x"1F36",x"2467",
        x"1F36",x"1288",x"0506",x"FC9A",x"FAFA",x"FD99",x"007F"
    );

    -- 移位寄存器存储输入数据
    signal sym_reg          : ARRAY12(L_filter - 1 downto 0);
    
    -- 插零相关信号
    signal insert_zero_en   : std_logic;
    signal insert_zero_data : std_logic_vector(W_in-1 downto 0);
    
    -- 计数器信号
    signal cnt_tmp4         : std_logic_vector(7 downto 0);
    signal cnt_tmp33        : std_logic_vector(3 downto 0);
    signal insert_entet     : std_logic;
    
    -- 使能信号相关
    signal en_tmp1          : std_logic;
    signal en_d1            : std_logic;
    signal sym_regen        : std_logic;
    signal sym_regen_d1     : std_logic;
    signal sym_regen_d2     : std_logic;
    signal en_tmp           : std_logic;
    
    -- DSP48E2相关信号
    signal dsp_a            : std_logic_vector(29 downto 0);  -- A输入 (数据)
    signal dsp_b            : std_logic_vector(17 downto 0);  -- B输入 (系数)
    signal dsp_c            : std_logic_vector(47 downto 0);  -- C输入 (累加器反馈)
    signal dsp_p            : std_logic_vector(47 downto 0);  -- P输出
    signal dsp_pcin         : std_logic_vector(47 downto 0);  -- 级联输入
    signal dsp_pcout        : std_logic_vector(47 downto 0);  -- 级联输出
    
    -- DSP控制信号
    signal alumode          : std_logic_vector(3 downto 0);
    signal inmode           : std_logic_vector(4 downto 0);
    signal opmode           : std_logic_vector(8 downto 0);
    signal carryin          : std_logic;
    signal carryinsel       : std_logic_vector(2 downto 0);
    
    -- MAC操作相关信号
    signal mac_result       : std_logic_vector(47 downto 0);
    signal mac_valid        : std_logic;
    signal mac_counter      : std_logic_vector(3 downto 0); --计数当前处理的滤波器抽头序号（0~14对应15阶）
    signal mac_start        : std_logic;    --启动乘累加(MAC)操作的使能信号
    signal mac_done         : std_logic;
    
    -- 当前处理的系数和数据索引
    signal coef_index       : std_logic_vector(3 downto 0);
    signal mult_data        : std_logic_vector(11 downto 0);
    signal mult_coef        : std_logic_vector(15 downto 0);--当前使用的系数索引（与mac_counter同步）
    signal mult_result      : std_logic_vector(47 downto 0);
    
    -- 输出相关信号
    signal ovtmpdata        : std_logic_vector(11 downto 0);
    signal otmpen           : std_logic;

begin

    -- 使能信号处理 
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

    -- 8位计数器 
    process(i_clk,i_rst)begin
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

    -- 插零使能生成 
    process(i_clk,i_rst)begin
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

    -- 4位模16计数器 
    cnt33: process(i_clk,i_rst)
    begin
       if i_rst = '1' then
          cnt_tmp33 <= (others=>'0');
       elsif (i_clk='1' and i_clk'event) then
          if(sym_regen_d1 = '1'and sym_regen_d2='0') then
              cnt_tmp33 <= "0001";
          elsif(cnt_tmp33 >0)then
               if(cnt_tmp33=15)then
                  cnt_tmp33 <= "0000";  
               else
                  cnt_tmp33 <= cnt_tmp33 + "0001";
               end if;
          end if;
       end if;
    end process;

    -- 插零数据生成 
    insert_gen : process(i_clk,i_rst)begin
        if i_rst = '1' then
            insert_zero_en <= '0';
            insert_zero_data <= (others => '0');
        elsif (i_clk='1' and i_clk'event) then
            insert_zero_en <= insert_entet or i_en;
            insert_zero_data <= iv_data;
        end if;
    end process;

    -- 数据移位寄存器 
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

    -- MAC控制逻辑
    mac_control : process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            mac_counter <= (others => '0');
            mac_start <= '0';
            mac_done <= '0';
            coef_index <= (others => '0');
        elsif rising_edge(i_clk) then
            -- 检测计算开始条件
            if cnt_tmp33 = "0001" and sym_regen_d1 = '1' then
                mac_start <= '1';
                mac_counter <= "0001";
                coef_index <= "0000";
                mac_done <= '0';
            elsif mac_start = '1' and mac_counter < 15 then
                mac_counter <= mac_counter + 1;
                coef_index <= coef_index + 1;
            elsif mac_counter = 15 then
                mac_start <= '0';
                mac_done <= '1';
                mac_counter <= (others => '0');
            else
                mac_done <= '0';
            end if;
        end if;
    end process;

    -- 数据和系数选择 (基于DSP的实现)
    mult_data_sel : process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            mult_data <= (others => '0');
            mult_coef <= (others => '0');
        elsif rising_edge(i_clk) then
            if mac_start = '1' then
                case coef_index is
                    when "0000" => mult_coef <= filter_coef(0);  mult_data <= sym_reg(0);
                    when "0001" => mult_coef <= filter_coef(1);  mult_data <= sym_reg(1);
                    when "0010" => mult_coef <= filter_coef(2);  mult_data <= sym_reg(2);
                    when "0011" => mult_coef <= filter_coef(3);  mult_data <= sym_reg(3);
                    when "0100" => mult_coef <= filter_coef(4);  mult_data <= sym_reg(4);
                    when "0101" => mult_coef <= filter_coef(5);  mult_data <= sym_reg(5);
                    when "0110" => mult_coef <= filter_coef(6);  mult_data <= sym_reg(6);
                    when "0111" => mult_coef <= filter_coef(7);  mult_data <= sym_reg(7);
                    when "1000" => mult_coef <= filter_coef(8);  mult_data <= sym_reg(8);
                    when "1001" => mult_coef <= filter_coef(9);  mult_data <= sym_reg(9);
                    when "1010" => mult_coef <= filter_coef(10); mult_data <= sym_reg(10);
                    when "1011" => mult_coef <= filter_coef(11); mult_data <= sym_reg(11);
                    when "1100" => mult_coef <= filter_coef(12); mult_data <= sym_reg(12);
                    when "1101" => mult_coef <= filter_coef(13); mult_data <= sym_reg(13);
                    when "1110" => mult_coef <= filter_coef(14); mult_data <= sym_reg(14);
                    when others => mult_coef <= (others => '0'); mult_data <= (others => '0');
                end case;
            end if;
        end if;
    end process;

    -- DSP48E2控制信号设置
    alumode <= "0000";  -- Z + (X + Y + CIN)
    inmode <= "00000";  -- A1 and B1 registers bypassed
    carryinsel <= "000"; -- CARRYIN
    carryin <= '0';
    
    -- OPMODE控制MAC操作
    opmode <= "000110101" when mac_counter = 1 else  -- P = A*B (第一次乘法)
              "001110101";                            -- P = P + A*B (累加)

    -- DSP输入信号准备
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            dsp_a <= (others => '0');
            dsp_b <= (others => '0');
        elsif rising_edge(i_clk) then
            -- A输入：数据 (符号扩展到30位)
            if mult_data /= 0 and mult_data(11) = '1' then
                dsp_a <= "111111111111111111" & mult_data; -- 负数符号扩展
            else
                dsp_a <= "000000000000000000" & mult_data; -- 正数符号扩展
            end if;
            
            -- B输入：系数 (符号扩展到18位)
            if mult_coef(15) = '1' then
                -- 负数系数：高2位为1
                dsp_b <= "11" & mult_coef;
            else
                -- 正数系数：高2位为0
                dsp_b <= "00" & mult_coef;
            end if;
        end if;
    end process;

    -- DSP48E2实例化
    DSP48E2_inst : DSP48E2
    generic map (
        -- 配置参数
        ACASCREG => 1,
        ADREG => 1,
        ALUMODEREG => 1,
        AREG => 1,
        AUTORESET_PATDET => "NO_RESET",
        A_INPUT => "DIRECT",
        BCASCREG => 1,
        BREG => 1,
        B_INPUT => "DIRECT",
        CARRYINREG => 1,
        CARRYINSELREG => 1,
        CREG => 1,
        DREG => 1,
        INMODEREG => 1,
        MASK => X"3FFFFFFFFFFF",
        MREG => 1,-- 乘法结果寄存
        OPMODEREG => 1,
        PATTERN => X"000000000000",
        PREG => 1,
        SEL_MASK => "MASK",
        SEL_PATTERN => "PATTERN",
        USE_MULT => "MULTIPLY",-- 启用硬件乘法器
        USE_PATTERN_DETECT => "NO_PATDET",
        USE_SIMD => "ONE48"
    )
    port map (
        -- 级联端口
        ACOUT => open,
        BCOUT => open,
        CARRYCASCOUT => open,
        MULTSIGNOUT => open,
        PCOUT => dsp_pcout,
        
        -- 控制输出
        OVERFLOW => open,
        PATTERNBDETECT => open,
        PATTERNDETECT => open,
        UNDERFLOW => open,
        
        -- 数据输出
        CARRYOUT => open,
        P => dsp_p,
        
        -- 数据输入
        A => dsp_a, -- 30位有符号数据（来自sym_reg移位寄存器）
        ACIN => (others => '0'),-- 18位有符号系数（来自filter_coef数组）
        ALUMODE => alumode,
        B => dsp_b,
        BCIN => (others => '0'),
        C => (others => '0'),
        CARRYCASCIN => '0',
        CARRYIN => carryin,
        CARRYINSEL => carryinsel,
        CEA1 => '1',-- 使能A端口第一级寄存器
        CEA2 => '1',-- 使能B端口第一级寄存器
        CEAD => '1',
        CEALUMODE => '1',
        CEB1 => '1',
        CEB2 => '1',
        CEC => '1',
        CECARRYIN => '1',
        CECTRL => '1',
        CED => '1',
        CEINMODE => '1',
        CEM => '1',-- 乘法器寄存器时钟使能
        CEP => '1',
        CLK => i_clk,-- 同步时钟驱动
        D => (others => '0'),
        INMODE => inmode,
        MULTSIGNIN => '0',
        OPMODE => opmode,
        PCIN => dsp_pcin,
        RSTA => i_rst,
        RSTALLCARRYIN => i_rst,
        RSTALUMODE => i_rst,
        RSTB => i_rst,
        RSTC => i_rst,
        RSTCTRL => i_rst,
        RSTD => i_rst,
        RSTINMODE => i_rst,
        RSTM => i_rst,
        RSTP => i_rst
    );

    -- MAC结果捕获
    mac_result_capture : process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            mac_result <= (others => '0');
            mac_valid <= '0';
        elsif rising_edge(i_clk) then
            if mac_done = '1' then
                mac_result <= dsp_p;
                mac_valid <= '1';
            else
                mac_valid <= '0';
            end if;
        end if;
    end process;

    -- 使能信号生成
    entmp_gen : process(i_clk,i_rst)
    begin
        if i_rst = '1' then
            en_tmp <= '0';
        elsif (i_clk='1' and i_clk'event) then
            en_tmp <= mac_valid;
        end if;
    end process;

    -- 输出数据处理 
    out_gen:process(i_clk,i_rst) 
    begin
        if(i_rst='1')then
            ovtmpdata<=(others=>'0');
            otmpen <= '0';
        elsif(i_clk'event and i_clk='1' )then
            otmpen <= en_tmp;
            ovtmpdata <= mac_result(17 downto 6) + (not(mac_result(17)) and mac_result(5)); 
        end if;
    end process;

    -- 最终输出 
    process(i_clk,i_rst)begin
          if(i_rst='1')then
              o_data_en<='0';
              ov_data<=(others=>'0');
          elsif(i_clk'event and i_clk='1')then
              ov_data <= ovtmpdata(10 downto 0) &'0';
              ov_data(11) <= ovtmpdata(11);
              o_data_en <= otmpen;
           end if;
      end process;

end Behavioral;