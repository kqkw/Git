library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.std_logic_arith.ALL;
use IEEE.std_logic_unsigned.ALL;
use IEEE.numeric_std.ALL;

entity train_1 is
    generic(
        W_in        :   integer     :=12;       --input bit width
        W_filter    :   integer     :=16;       --filter width
        L_filter    :   integer     :=15;       --filter length
        L_multout   :   integer     :=18        --³Ë·¨Æ÷Êä³öÎ»¿í
    );
    port(
        i_clk       :   in std_logic;
        i_rst       :   in std_logic;
        iv_data     :   in std_logic_vector(W_in-1 downto 0);
        i_en        :   in std_logic;
        ov_data     :   out std_logic_vector(W_in-1 downto 0);
        o_data_en   :   out std_logic
    );
end train_1;

architecture Behavioral of train_1 is
component SignedDataRounding is
    generic(
        I_MSB       :       integer;
        O_MSB       :       integer;
        O_LSB       :       integer
    );
    port(
        i_clk       :       in std_logic;
        i_rst       :       in std_logic;
        
        i_data_en   :       in std_logic;
        iv_data     :       in std_logic_vector(I_MSB downto 0);
        
        o_data_en   :       out std_logic;
        ov_data     :       out std_logic_vector(O_MSB-O_LSB downto 0)
    );
end component;
        type ARRAY12 is array(NATURAL RANGE<>) of std_logic_vector(W_in-1 downto 0);
        signal sym_reg : ARRAY12(L_filter-1 downto 0);
        
        type ARRAY16 is array(NATURAL RANGE<>) of std_logic_vector(W_filter downto 0);
        constant filter_coef : ARRAY16(14 downto 0) := (
                    x"007F", x"FD99", x"FAFA", x"FC9A", x"0506", 
                    x"1288", x"1F36", x"2467", x"1F36", x"1288",
                    x"0506", x"FC9A", x"FAFA", x"FD99", x"007F");

        signal cnt_tmp : std_logic_vector(3 downto 0);
        signal en_tmp1 : std_logic;
        signal en_d1 : std_logic;
        signal sym_regen : std_logic;
        signal sym_regen_d1 : std_logic;
        signal sym_regen_d2 : std_logic;
        signal insert_zero_en : std_logic;
        signal cnt_tmp8 : std_logic_vector(7 downto 0);
        signal insert_entent : std_logic;
        signal insert_zero_data : std_logic_vector(W_in-1 downto 0);
        signal cnt_mod16 : std_logic_vector(3 downto 0);
        signal multcoef : std_logic_vector(15 downto 0);
        signal multdata : std_logic_vector(W_in downto 0);
        signal multout : std_logic_vector(15 downto 0);
        signal sumout : std_logic_vector(17 downto 0);
        signal en_tmp: std_logic;
        
        signal ovtmpdata:std_logic_vector(11 downto 0);
        signal otmpen:std_logic;
begin

entmp1 : process(i_clk,i_rst)
begin
    if i_rst='1' then
        en_tmp1<='0';
    elsif(i_clk='1' and i_clk'event) then 
        if(i_en='1') then
            en_tmp1<='1';
        end if;
    end if;       
end process;

cnt_gen : process(i_clk,i_rst)
begin
    if i_rst='1' then
        cnt_tmp <= (others=>'0');
    elsif(i_clk='1' and i_clk'event) then
        if i_en='1' then 
            cnt_tmp<="0001";
        else
            cnt_tmp<=cnt_tmp+en_tmp1;
        end if;
    end if;
end process;        

entmp_delay : process(i_clk,i_rst)
begin
    if i_rst='1' then 
        en_d1 <= '0';
        sym_regen <= '0';
        sym_regen_d1 <='0';
        sym_regen_d2 <='0';
    elsif(i_clk='1' and i_clk'event) then
        en_d1 <= i_en;
        sym_regen <= insert_zero_en;
        sym_regen_d1<=sym_regen;
        sym_regen_d2<=sym_regen_d1;
    end if;
end process;

process(i_clk,i_rst)
begin
    if i_rst='1' then 
        cnt_tmp8<=(others=>'0');
    elsif(i_clk='1' and i_clk'event) then
        if(i_en='1' and en_d1='0') then 
            cnt_tmp8<="00000001";
        elsif (cnt_tmp8>0) then
            if(cnt_tmp8=63)then
                cnt_tmp8<="00000000";
            else
                cnt_tmp8<=cnt_tmp8+"00000001";
            end if;
        end if;
    end if;
end process;

process(i_clk,i_rst)
begin
    if(i_rst='1') then
        insert_entent<='0';
    elsif(i_clk='1' and i_clk'event) then
        if(cnt_tmp8=15 or cnt_tmp8=31 or cnt_tmp8=47 or cnt_tmp8=63) then
            insert_entent<='1'; 
        else
            insert_entent<='0';
        end if;
    end if;
end process;

insert_gen:process(i_clk,i_rst)
begin
    if i_rst='1'then
        insert_zero_en<='0';
        insert_zero_data<=(others=>'0');
    elsif(i_clk='1' and i_clk'event) then
        insert_zero_en<=insert_entent or i_en;
        insert_zero_data<=iv_data;
    end if;
end process;

data_flow: process(i_rst,i_clk)
begin
    if(i_clk='1' and i_clk'event) then
        if(i_rst='1') then
            sym_reg<=(others=>(others=>'0'));
        elsif(insert_zero_en='1') then
            for i in 0 to L_filter-2 loop
                sym_reg(i+1)<=sym_reg(i);
            end loop;
            sym_reg(0)<=insert_zero_data;    
        else    
            sym_reg<=sym_reg;
        end if;
    end if;
end process;

mod16: process(i_clk,i_rst)
begin
    if i_rst='1' then
        cnt_mod16<=(others=>'0');
    elsif (i_clk='1' and i_clk'event) then
        if(sym_regen_d1='1' and sym_regen_d2='0') then
            cnt_mod16<="0001";
        elsif(cnt_mod16>0)then
            if(cnt_mod16=15)then
                cnt_mod16<="0000";
            else
                cnt_mod16<=cnt_mod16+"0001";
            end if;
        end if;
    end if;
end process;

coef_data_select: process(i_clk,i_rst)
begin
    if(i_clk='1' and i_clk'event) then
        if(i_rst='1') then
            multcoef<=(others=>'0');
            multdata<=(others=>'0');
        else
            case(cnt_tmp) is
                when "0010"=>
                    multcoef<=filter_coef(0);
                    multdata<=sym_reg(0);
                when "0011"=>
                    multcoef<=filter_coef(1);
                    multdata<=sym_reg(1);
                when "0100"=>
                    multcoef<=filter_coef(2);
                    multdata<=sym_reg(2);
                when "0101"=>
                    multcoef<=filter_coef(3);
                    multdata<=sym_reg(3);
                when "0110"=>
                    multcoef<=filter_coef(4);
                    multdata<=sym_reg(4);
                when "0111"=>
                    multcoef<=filter_coef(5);
                    multdata<=sym_reg(5);
                when "1000"=>
                    multcoef<=filter_coef(6);
                    multdata<=sym_reg(6);
                when "1001"=>
                    multcoef<=filter_coef(7);
                    multdata<=sym_reg(7);
                when "1010"=>
                    multcoef<=filter_coef(8);
                    multdata<=sym_reg(8);
                when "1011"=>
                    multcoef<=filter_coef(9);
                    multdata<=sym_reg(9);
                when "1100"=>
                    multcoef<=filter_coef(10);
                    multdata<=sym_reg(10);
                when "1101"=>
                    multcoef<=filter_coef(11);
                    multdata<=sym_reg(11);  
                when "1110"=>
                    multcoef<=filter_coef(12);
                    multdata<=sym_reg(12);
                when "1111"=>
                    multcoef<=filter_coef(13);
                    multdata<=sym_reg(13);
                when "0000"=>
                    multcoef<=filter_coef(14);
                    multdata<=sym_reg(14);
                when others=>
                    multcoef<=(others=>'0');
                    multdata<=(others=>'0');  
            end case;
        end if;
    end if;
end process;

mult_gen:process(i_clk,i_rst)
begin
    if(i_rst='1')then
        multout<=(others=>'0');
    elsif(i_clk='1' and i_clk'event) then
        if(multdata/=0 and multdata(11)='1') then
            multout<=0-multcoef;
        elsif(multdata/=0 and multdata(11)='0') then
            multout<=multcoef;
        elsif(multdata=0)then
            multout<=(others=>'0');
        end if;
    end if;
end process;

sum_gen:process(i_clk,i_rst)
variable entmp4:std_logic;
begin
    if i_rst='1' then
        sumout<=(others=>'0');
        entmp4:='0';
    elsif (i_clk='1' and i_clk'event) then
        entmp4:=en_tmp or sym_regen_d1;
        if(cnt_mod16>=1 and cnt_mod16<=14) then
            sumout<=sumout+sxt(multout,18);
        elsif(cnt_mod16=0 and entmp4='1') then
            sumout<=sxt(multout,18);
        elsif(cnt_mod16=0 and entmp4='0')then
            sumout<=(others=>'0');
        end if;
    end if;
end process;

entmp_gen: process(i_clk,i_rst)
begin
    if i_rst='1' then
        en_tmp<='0';
    elsif(i_clk='1' and i_clk'event) then
        if(cnt_mod16=15) then
            en_tmp<='1';
        else
            en_tmp<='0';
        end if;
    end if;
end process;


out_gen:process(i_clk,i_rst)
begin
    if(i_rst='1')then
        ovtmpdata<=(others=>'0');
        otmpen<='0';
    elsif(i_clk='1' and i_clk'event) then
        otmpen<=en_tmp;
        ovtmpdata<=sumout(17 downto 6)+(not(sumout(17)) and sumout(5));
    end if;
end process;

process(i_clk,i_rst)
begin
    if(i_rst='1')then
        o_data_en<='0';
        ov_data<=(others=>'0');
    elsif(i_clk='1' and i_clk'event) then
        ov_data<=ovtmpdata(10 downto 0) &'0';
        ov_data(11)<=ovtmpdata(11);
        o_data_en<=otmpen;
    end if;
end process;

end Behavioral; 