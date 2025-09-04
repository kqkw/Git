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
-- ʹ��DSP48E2ʵ����ͬ��SRRC�˲�����
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;
use IEEE.NUMERIC_STD.all;

-- Xilinx DSP��
library UNISIM;
use UNISIM.VComponents.all;

entity Musig_uplink_tx_module_signaling_srrc_dsp is
   generic (
        W_in           :     integer := 12;  -- ����λ��   
        W_filter       :     integer := 16;  -- �˲���ϵ��λ��
        L_filter       :     integer := 15;  -- �˲������� 
        L_multOut      :     integer := 18   -- �˷������λ��
    );
    Port ( 
        i_clk          :     in   std_logic;
        i_rst          :     in   std_logic;
        iv_data        :     in   std_logic_vector(W_in-1 downto 0);    -- ������������
        i_en           :     in   std_logic;    -- ����ʹ���ź�
       
        ov_data        :     out  std_logic_vector(W_in-1 downto 0);    -- �����������
        o_data_en      :     out  std_logic     -- ���������Ч�ź�
    );
end Musig_uplink_tx_module_signaling_srrc_dsp;

architecture Behavioral of Musig_uplink_tx_module_signaling_srrc_dsp is

    -- �������Ͷ���
    type ARRAY12 is array (NATURAL RANGE <>) of std_logic_vector(W_in - 1 downto 0);
    type ARRAY16 is array (NATURAL RANGE <>) of std_logic_vector(W_filter - 1 downto 0);
    
    -- �˲���ϵ�� 
    constant filter_coef : ARRAY16(14 downto 0) := (
        x"007F",x"FD99",x"FAFA",x"FC9A",x"0506",x"1288",x"1F36",x"2467",
        x"1F36",x"1288",x"0506",x"FC9A",x"FAFA",x"FD99",x"007F"
    );

    -- ��λ�Ĵ����洢��������
    signal sym_reg          : ARRAY12(L_filter - 1 downto 0);
    
    -- ��������ź�
    signal insert_zero_en   : std_logic;
    signal insert_zero_data : std_logic_vector(W_in-1 downto 0);
    
    -- �������ź�
    signal cnt_tmp4         : std_logic_vector(7 downto 0);
    signal cnt_tmp33        : std_logic_vector(3 downto 0);
    signal insert_entet     : std_logic;
    
    -- ʹ���ź����
    signal en_tmp1          : std_logic;
    signal en_d1            : std_logic;
    signal sym_regen        : std_logic;
    signal sym_regen_d1     : std_logic;
    signal sym_regen_d2     : std_logic;
    signal en_tmp           : std_logic;
    
    -- DSP48E2����ź�
    signal dsp_a            : std_logic_vector(29 downto 0);  -- A���� (����)
    signal dsp_b            : std_logic_vector(17 downto 0);  -- B���� (ϵ��)
    signal dsp_c            : std_logic_vector(47 downto 0);  -- C���� (�ۼ�������)
    signal dsp_p            : std_logic_vector(47 downto 0);  -- P���
    signal dsp_pcin         : std_logic_vector(47 downto 0);  -- ��������
    signal dsp_pcout        : std_logic_vector(47 downto 0);  -- �������
    
    -- DSP�����ź�
    signal alumode          : std_logic_vector(3 downto 0);
    signal inmode           : std_logic_vector(4 downto 0);
    signal opmode           : std_logic_vector(8 downto 0);
    signal carryin          : std_logic;
    signal carryinsel       : std_logic_vector(2 downto 0);
    
    -- MAC��������ź�
    signal mac_result       : std_logic_vector(47 downto 0);
    signal mac_valid        : std_logic;
    signal mac_counter      : std_logic_vector(3 downto 0); --������ǰ������˲�����ͷ��ţ�0~14��Ӧ15�ף�
    signal mac_start        : std_logic;    --�������ۼ�(MAC)������ʹ���ź�
    signal mac_done         : std_logic;
    
    -- ��ǰ�����ϵ������������
    signal coef_index       : std_logic_vector(3 downto 0);
    signal mult_data        : std_logic_vector(11 downto 0);
    signal mult_coef        : std_logic_vector(15 downto 0);--��ǰʹ�õ�ϵ����������mac_counterͬ����
    signal mult_result      : std_logic_vector(47 downto 0);
    
    -- �������ź�
    signal ovtmpdata        : std_logic_vector(11 downto 0);
    signal otmpen           : std_logic;

begin

    -- ʹ���źŴ��� 
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

    -- 8λ������ 
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

    -- ����ʹ������ 
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

    -- 4λģ16������ 
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

    -- ������������ 
    insert_gen : process(i_clk,i_rst)begin
        if i_rst = '1' then
            insert_zero_en <= '0';
            insert_zero_data <= (others => '0');
        elsif (i_clk='1' and i_clk'event) then
            insert_zero_en <= insert_entet or i_en;
            insert_zero_data <= iv_data;
        end if;
    end process;

    -- ������λ�Ĵ��� 
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

    -- MAC�����߼�
    mac_control : process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            mac_counter <= (others => '0');
            mac_start <= '0';
            mac_done <= '0';
            coef_index <= (others => '0');
        elsif rising_edge(i_clk) then
            -- �����㿪ʼ����
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

    -- ���ݺ�ϵ��ѡ�� (����DSP��ʵ��)
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

    -- DSP48E2�����ź�����
    alumode <= "0000";  -- Z + (X + Y + CIN)
    inmode <= "00000";  -- A1 and B1 registers bypassed
    carryinsel <= "000"; -- CARRYIN
    carryin <= '0';
    
    -- OPMODE����MAC����
    opmode <= "000110101" when mac_counter = 1 else  -- P = A*B (��һ�γ˷�)
              "001110101";                            -- P = P + A*B (�ۼ�)

    -- DSP�����ź�׼��
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            dsp_a <= (others => '0');
            dsp_b <= (others => '0');
        elsif rising_edge(i_clk) then
            -- A���룺���� (������չ��30λ)
            if mult_data /= 0 and mult_data(11) = '1' then
                dsp_a <= "111111111111111111" & mult_data; -- ����������չ
            else
                dsp_a <= "000000000000000000" & mult_data; -- ����������չ
            end if;
            
            -- B���룺ϵ�� (������չ��18λ)
            if mult_coef(15) = '1' then
                -- ����ϵ������2λΪ1
                dsp_b <= "11" & mult_coef;
            else
                -- ����ϵ������2λΪ0
                dsp_b <= "00" & mult_coef;
            end if;
        end if;
    end process;

    -- DSP48E2ʵ����
    DSP48E2_inst : DSP48E2
    generic map (
        -- ���ò���
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
        MREG => 1,-- �˷�����Ĵ�
        OPMODEREG => 1,
        PATTERN => X"000000000000",
        PREG => 1,
        SEL_MASK => "MASK",
        SEL_PATTERN => "PATTERN",
        USE_MULT => "MULTIPLY",-- ����Ӳ���˷���
        USE_PATTERN_DETECT => "NO_PATDET",
        USE_SIMD => "ONE48"
    )
    port map (
        -- �����˿�
        ACOUT => open,
        BCOUT => open,
        CARRYCASCOUT => open,
        MULTSIGNOUT => open,
        PCOUT => dsp_pcout,
        
        -- �������
        OVERFLOW => open,
        PATTERNBDETECT => open,
        PATTERNDETECT => open,
        UNDERFLOW => open,
        
        -- �������
        CARRYOUT => open,
        P => dsp_p,
        
        -- ��������
        A => dsp_a, -- 30λ�з������ݣ�����sym_reg��λ�Ĵ�����
        ACIN => (others => '0'),-- 18λ�з���ϵ��������filter_coef���飩
        ALUMODE => alumode,
        B => dsp_b,
        BCIN => (others => '0'),
        C => (others => '0'),
        CARRYCASCIN => '0',
        CARRYIN => carryin,
        CARRYINSEL => carryinsel,
        CEA1 => '1',-- ʹ��A�˿ڵ�һ���Ĵ���
        CEA2 => '1',-- ʹ��B�˿ڵ�һ���Ĵ���
        CEAD => '1',
        CEALUMODE => '1',
        CEB1 => '1',
        CEB2 => '1',
        CEC => '1',
        CECARRYIN => '1',
        CECTRL => '1',
        CED => '1',
        CEINMODE => '1',
        CEM => '1',-- �˷����Ĵ���ʱ��ʹ��
        CEP => '1',
        CLK => i_clk,-- ͬ��ʱ������
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

    -- MAC�������
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

    -- ʹ���ź�����
    entmp_gen : process(i_clk,i_rst)
    begin
        if i_rst = '1' then
            en_tmp <= '0';
        elsif (i_clk='1' and i_clk'event) then
            en_tmp <= mac_valid;
        end if;
    end process;

    -- ������ݴ��� 
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

    -- ������� 
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