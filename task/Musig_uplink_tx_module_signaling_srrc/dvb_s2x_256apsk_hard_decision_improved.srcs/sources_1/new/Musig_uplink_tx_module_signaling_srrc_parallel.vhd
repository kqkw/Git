----------------------------------------------------------------------------------
-- Company: 
-- Engineer:    Chu lei
-- 
-- Create Date: 2025/04/14 10:39:09
-- Design Name: 
-- Module Name: Musig_uplink_tx_module_signaling_srrc - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Revision 0.1 - GONG: 2025-4-22, Not simple enough, to be revised
-- Revision 0.2- Chu Lei: 2025-4-24, use add to replace mult since input is 1 or 0
-- Revision 0.3- Chu Lei: 2025-5-7, Modify the output enable signal as well as the logic
-- Additional Comments:
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;
--use ieee.std_logic_textio.all;
--use std.textio.all;
use IEEE.NUMERIC_STD.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity Musig_uplink_tx_module_signaling_srrc is
   generic (
        W_in           :     integer := 12;  -- Input bit width   
        W_filter       :     integer := 16;  -- Filter width
        L_filter       :     integer := 15;  -- Filter length 
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
end Musig_uplink_tx_module_signaling_srrc;

architecture Behavioral of Musig_uplink_tx_module_signaling_srrc is

component SignedDataRounding is
    generic(
        I_MSB       :       integer ;   -- �������ݵ������Чλ(MSB)λ��
        O_MSB       :       integer ;   -- ������ݵ������Чλλ��
        O_LSB       :       integer     -- ������ݵ������Чλλ��
    );
    Port( 
        i_clk       :       in  std_logic;
        i_rst       :       in  std_logic;
    
        i_data_en   :       in  std_logic;  -- ����������Ч��־
        iv_data     :       in  std_logic_vector(I_MSB downto 0);
                
        o_data_en   :       out std_logic;
        ov_data     :       out std_logic_vector(O_MSB-O_LSB downto 0)
    );
end component;
        
        type ARRAY12 is array (NATURAL RANGE <>) of std_logic_vector(W_in - 1 downto 0);  -- 4.8  �洢12λ����ź�����(��������λ��W_in=12)  (4λ������8λС��)
        type ARRAY13 is array (NATURAL RANGE <>) of std_logic_vector(W_in downto 0);
    
        type ARRAY16 is array (NATURAL RANGE <>) of std_logic_vector(W_filter - 1 downto 0); -- 4.12  �洢�˲���ϵ��(W_filter=16)
        type ARRAY19 is array (NATURAL RANGE <>) of std_logic_vector(L_multOut downto 0);  -- 5.14  �洢�˷��ۼӽ��

        signal sym_reg   :    ARRAY12(L_filter - 1 downto 0); -- 14 downto 0    15��(L_filter=15)12λ��λ�Ĵ���
        signal multData1 :    std_logic_vector(W_in-1 downto 0);    -- 12λ����(��������)
        signal multCoef1 :    std_logic_vector(15 downto 0);    -- 16λ������(�˲���ϵ��)
        signal multOut1  :    std_logic_vector(15 downto 0);    -- 16λ�˻����
        signal sumOut    :    std_logic_vector(17 downto 0);    --�洢15���˷�������ۼӺ�
        signal insert_zero_en     :    std_logic;   -- ����ʹ���ź�
        signal insert_zero_data   :    std_logic_vector(W_in-1 downto 0);   -- ��������
        signal en_tmp : std_logic;  -- ��ʱʹ��
        signal en_d1 : std_logic;   -- ʹ���ź��ӳ�1��
        signal en_tmp1 : std_logic; -- ��һ����ʱʹ��
     --   signal en_tmp1_d1 : std_logic;
     --   signal en_tmp1_d2 : std_logic;
        signal cnt_tmp   : std_logic_vector(3 downto 0);    -- 4λ������
     --   signal cnt_tmp3 : std_logic_vector(3 downto 0);

------------------------- test cnt  ---------------------------------
        signal cnt_tmp4 : std_logic_vector(7 downto 0); 
        signal insert_entet : std_logic;    --����ѵ������ʹ��
        signal sym_regen : std_logic;   -- �����������ź�
        signal sym_regen_d1 : std_logic;    -- �ӳ�1��
        signal sym_regen_d2 : std_logic;
        signal cnt_tmp33 : std_logic_vector(3 downto 0);
---------------------------------------------------------------------

     --   constant filter_coef : ARRAY16(14 downto 0) := (x"FEC7",x"FB11",x"F9BE",x"FD97",x"0727",x"13C3",x"1E86",x"22C0",x"1E86",x"13C3",x"0727",x"FD97",x"F9BE",x"FB11",x"FEC7");  -- 2.14 15order
      --  constant filter_coef : ARRAY16(14 downto 0) := (x"00FE",x"FB32",x"F5F4",x"F934",x"0A0C",x"2510",x"3E6B",x"48CE",x"3E6B",x"2510",x"0A0C",x"F934",x"F5F4",x"FB32",x"00FE");  -- COEF *2
        constant filter_coef : ARRAY16(14 downto 0) := (x"007F",x"FD99",x"FAFA",x"FC9A",x"0506",x"1288",x"1F36",x"2467",x"1F36",x"1288",x"0506",x"FC9A",x"FAFA",x"FD99",x"007F"); -- srrc 0.5    �˲���ϵ������

        signal ovtmpdata : std_logic_vector( 11 downto 0);  ---- 12λ��ʱ���
        signal otmpen : std_logic;  -- ���ʹ���ź�

        
begin

entmp1 : process(i_clk,i_rst)   --����ʹ���ź�(i_en)��Чʱ��en_tmp1��Ϊ�ߵ�ƽ�����ڸ�λʱ����
begin
    if i_rst = '1' then
          en_tmp1 <= '0';
    elsif (i_clk='1' and i_clk'event) then  ---- ʱ�������ش���
        if(i_en='1')then
          en_tmp1 <= '1';
        end if;
    end if;
end process;

entmp_delay : process(i_clk,i_rst)
begin
    if i_rst = '1' then
       --  en_tmp1_d1 <= '0';
      --   en_tmp1_d2 <= '0';
         en_d1 <= '0';
         sym_regen <= '0';
         sym_regen_d1 <= '0';
         sym_regen_d2 <= '0';
    elsif (i_clk='1' and i_clk'event) then
         en_d1 <= i_en;
         sym_regen <= insert_zero_en;
         sym_regen_d1 <= sym_regen; -- �ӳ�1����
         sym_regen_d2 <= sym_regen_d1;  -- �ӳ�2����
       --  en_tmp1_d1 <= en_tmp1;
      --   en_tmp1_d2 <= en_tmp1_d1;
    end if;
end process;

-- process(i_clk,i_rst)
-- begin
--     if i_rst = '1' then
--         cnt_tmp3 <= (others=>'0');
--     elsif (i_clk='1' and i_clk'event) then
--         if(en_tmp1_d2='1') then
--             cnt_tmp3 <= cnt_tmp3+"0001";
--         end if;
--     end if;
-- end process;

------------------  test cnt ---------------------
process(i_clk,i_rst)begin       --8λ������
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

  cnt33: process(i_clk,i_rst)       --��ʹ�ܿ��Ƶ�4λģ16������
  begin
     if i_rst = '1' then
        cnt_tmp33 <= (others=>'0');
     elsif (i_clk='1' and i_clk'event) then
        if(sym_regen_d1 = '1'and sym_regen_d2='0') then --�źŸոմӵ�����Ϊ�ߵ�ƽ��Ҳ���ǿ�ʼ����һ�������ݣ�
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
--------------------------------------------------
      
cnt_gen  : process(i_clk,i_rst)
begin
    if i_rst = '1' then
        cnt_tmp <= (others=>'0');
    elsif (i_clk='1' and i_clk'event) then
        if i_en = '1' then
            cnt_tmp <= "0001";
        else 
            cnt_tmp <= cnt_tmp +en_tmp1;    --����������en_tmp1�źž����Ƿ����
        end if;
    end if;
end process;

insert_gen : process(i_clk,i_rst)begin
    if i_rst = '1' then
        insert_zero_en <= '0';
        insert_zero_data <= (others => '0');
    elsif (i_clk='1' and i_clk'event) then
        insert_zero_en <= insert_entet or i_en;
        insert_zero_data <= iv_data;
    end if;
end process;

data_flow: process(i_rst,i_clk)     --ʹ����Чʱ���������λ�ƶ�һλ
    begin
        if(i_clk'event and i_clk = '1')then
            if(i_rst = '1') then
                sym_reg <= (others=>(others=>'0'));        
            elsif(insert_zero_en= '1') then
                for i in 0 to L_filter-2 loop  --reg shift
                    sym_reg(i+1) <= sym_reg(i); -- �������λ�ƶ�
                end loop;
                sym_reg(0) <= insert_zero_data;    -- ���λ����������
            else
                sym_reg<=sym_reg;
            end if;    
        end if;
    end process;


mult_data_sel1 : process(i_clk,i_rst)
    begin
        if(i_clk'event and i_clk='1')then
            if (i_rst='1')then
                multCoef1 <=(others=>'0');
                multData1 <=(others=>'0');
            else
                case(cnt_tmp) is
                    when "0010" =>
                        multCoef1 <= filter_coef(0);  
                        multData1 <= sym_reg(0);
                    when "0011" =>
                        multCoef1 <= filter_coef(1); 
                        multData1 <=  sym_reg(1);
                    when "0100" =>
                        multCoef1 <= filter_coef(2); 
                        multData1 <=  sym_reg(2);
                    when "0101" =>
                        multCoef1 <= filter_coef(3); 
                        multData1 <= sym_reg(3);
                    when "0110" =>
                        multCoef1 <= filter_coef(4); 
                        multData1 <= sym_reg(4);
                    when "0111" =>
                        multCoef1 <= filter_coef(5); 
                        multData1 <= sym_reg(5);
                    when "1000" =>
                        multCoef1 <= filter_coef(6); 
                        multData1 <= sym_reg(6);
                    when "1001" =>
                        multCoef1 <= filter_coef(7); 
                        multData1 <= sym_reg(7);
                    when "1010" =>
                        multCoef1 <= filter_coef(8); 
                        multData1 <= sym_reg(8);
                    when "1011" =>
                        multCoef1 <= filter_coef(9); 
                        multData1 <= sym_reg(9);
                    when "1100" =>
                        multCoef1 <= filter_coef(10); 
                        multData1 <= sym_reg(10);
                    when "1101" =>
                        multCoef1 <= filter_coef(11); 
                        multData1 <= sym_reg(11);
                    when "1110" =>
                        multCoef1 <= filter_coef(12); 
                        multData1 <= sym_reg(12);
                    when "1111" =>
                        multCoef1 <= filter_coef(13);
                        multData1 <= sym_reg(13);
                    when "0000" =>
                        multCoef1 <= filter_coef(14);
                        multData1 <= sym_reg(14);
                    when others =>
                        multCoef1 <=(others=>'0');
                        multData1 <=(others=>'0');
                end case;
            end if;
        end if;
    end process;


    mult_gen :  process(i_clk,i_rst) begin
         if(i_rst='1')then
            multOut1 <= (others=>'0');
         elsif(i_clk'event and i_clk='1')then
            if(multData1 /= 0 and multData1(11) = '1')then
                multOut1 <= 0-multCoef1;  
            elsif(multData1 /= 0 and multData1(11) = '0')then
                multOut1 <= multCoef1;
            elsif(multData1 = 0)then
                multOut1 <= (others=>'0');
            end if;
         end if;
    end process;

    -- sum_gen : process(i_clk,i_rst)
    -- begin
    --     if i_rst = '1' then
    --         sumOut <= (others=>'0');
    --     elsif (i_clk='1' and i_clk'event) then
    --         if(cnt_tmp33 >= 1 and cnt_tmp33<=14) then
    --             sumOut <= sumOut + sxt(multOut1,18);
    --         elsif(cnt_tmp33 = 0) then
    --             sumOut <= sxt(multOut1,18); -- 8.12
    --         end if;
    --     end if;
    -- end process;

    sum_gen : process(i_clk,i_rst)
    variable entmp4 : std_logic;
    begin
        if i_rst = '1' then
            sumOut <= (others=>'0');
            entmp4  := '0';
        elsif (i_clk='1' and i_clk'event) then
            entmp4 := en_tmp or sym_regen_d1;
            if(cnt_tmp33 >= 1 and cnt_tmp33<=14) then
                sumOut <= sumOut + sxt(multOut1,18);
            elsif(cnt_tmp33 = 0 and entmp4='1') then
                sumOut <= sxt(multOut1,18); -- 8.12
            elsif(cnt_tmp33 = 0 and entmp4='0') then
                sumOut <= (others=>'0');
            end if;
        end if;
    end process;

    entmp_gen : process(i_clk,i_rst)
    begin
        if i_rst = '1' then
            en_tmp <= '0';
        elsif (i_clk='1' and i_clk'event) then
            if(cnt_tmp33 = 15) then
                en_tmp <= '1';
            else
                en_tmp <= '0';
            end if;
        end if;
    end process;

out_gen:process(i_clk,i_rst) begin
    if(i_rst='1')then
        ovtmpdata<=(others=>'0');
        otmpen <= '0';
    elsif(i_clk'event and i_clk='1' )then
        otmpen <= en_tmp;
        ovtmpdata<=sumOut(17 downto 6)+(not(sumOut(17)) and sumOut(5)); 
    end if;
end process;


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