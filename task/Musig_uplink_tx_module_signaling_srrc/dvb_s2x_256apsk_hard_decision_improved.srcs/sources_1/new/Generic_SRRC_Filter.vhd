----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 2025/07/18
-- Design Name: 
-- Module Name: Generic_SRRC_Filter - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: ͨ�û�SRRC�˲�����֧�ֿ����õ��˲����������ϲ�����
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 1.0 - Generic Design with configurable parameters
-- Additional Comments:
-- ֧�ָ�����˲������������ͨ���Ժ�����
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
--use IEEE.STD_LOGIC_ARITH.all;
--use IEEE.STD_LOGIC_UNSIGNED.all;
use IEEE.NUMERIC_STD.all;

-- ͨ�û���SRRC�˲���ʵ��
entity Generic_SRRC_Filter is
    generic (
        -- ����λ�����
        W_INPUT           : integer := 12;   -- ��������λ��
        W_COEF            : integer := 16;   -- �˲���ϵ��λ��
        W_OUTPUT          : integer := 12;   -- �������λ��
        
        -- �˲�������
        FILTER_ORDER      : integer := 63;   -- �˲������� (������Ϊ15, 31, 63)
        UPSAMPLE_RATE     : integer := 4;    -- �ϲ����� (������Ϊ2, 4, 8��)
        
        -- ��ˮ�߲���
        PIPELINE_STAGES   : integer := 3;    -- ��ˮ�߼���
        
        -- �ۼ���λ�� 
        W_ACCUMULATOR     : integer := 24    -- �ۼ���λ��
    );
    Port ( 
        -- ʱ�Ӻ͸�λ
        i_clk             : in  std_logic;
        i_rst             : in  std_logic;
        
        -- ����ӿ�
        iv_data           : in  std_logic_vector(W_INPUT-1 downto 0);
        i_data_valid      : in  std_logic;
        o_data_ready      : out std_logic;
        
        -- ����ӿ�
        ov_data           : out std_logic_vector(W_OUTPUT-1 downto 0);
        o_data_valid      : out std_logic;
        i_data_ready      : in  std_logic;
        
        -- ���ýӿ�
        i_bypass          : in  std_logic;   -- ��·ģʽ
        i_reset_filter    : in  std_logic    -- �˲�����λ
    );
end Generic_SRRC_Filter;

architecture Behavioral of Generic_SRRC_Filter is

    -- ���Ͷ���
    type t_data_array is array (natural range <>) of std_logic_vector(W_INPUT-1 downto 0);
    type t_coef_array is array (natural range <>) of std_logic_vector(W_COEF-1 downto 0);
    type t_mult_array is array (natural range <>) of std_logic_vector(W_INPUT+W_COEF-1 downto 0);
    
    -- �������� - �˲���ϵ��
    -- ���ֽ�����ϵ��
    constant COEF_15_ORDER : t_coef_array(0 to 14) := (
        x"007F",x"FD99",x"FAFA",x"FC9A",x"0506",x"1288",x"1F36",x"2467",
        x"1F36",x"1288",x"0506",x"FC9A",x"FAFA",x"FD99",x"007F"
    );
    
    constant COEF_31_ORDER : t_coef_array(0 to 30) := (
        x"0008",x"FFF8",x"0004",x"FFF0",x"0012",x"FFDB",x"0038",x"FFA8",
        x"0088",x"FF3C",x"0126",x"FE78",x"0238",x"FD0C",x"0434",x"FAD8",
        x"0747",x"F6A4",x"0C7A",x"F004",x"1590",x"E5A0",x"2B4C",x"7FFF",
        x"2B4C",x"E5A0",x"1590",x"F004",x"0C7A",x"F6A4",x"0747"
    );
    
    constant COEF_63_ORDER : t_coef_array(0 to 62) := (
        -- 63��ϵ��
        x"0001",x"FFFF",x"0001",x"FFFF",x"0002",x"FFFD",x"0003",x"FFFB",
        x"0005",x"FFF8",x"0008",x"FFF4",x"000C",x"FFEF",x"0012",x"FFE8",
        x"001A",x"FFDF",x"0024",x"FFD4",x"0030",x"FFC7",x"003F",x"FFB7",
        x"0050",x"FFA5",x"0065",x"FF90",x"007D",x"FF78",x"0099",x"FF5D",
        x"00BA",x"FF3E",x"00E0",x"FF1B",x"010C",x"FEF3",x"013E",x"FEC6",
        x"0178",x"FE93",x"01BB",x"FE5A",x"0209",x"FE19",x"0264",x"FDCF",
        x"02CC",x"FD7C",x"0345",x"FD1E",x"03D2",x"FCB3",x"0475",x"FC39",
        x"0532",x"FBB0",x"0610",x"FB15",x"0714",x"FA66",x"0844"
    );
    
    -- ��̬ϵ��ѡ����
    function get_filter_coef(order : integer; index : integer) return std_logic_vector is
    begin
        case order is
            when 15 =>
                if index < 15 then
                    return COEF_15_ORDER(index);
                else
                    return (others => '0');
                end if;
            when 31 =>
                if index < 31 then
                    return COEF_31_ORDER(index);
                else
                    return (others => '0');
                end if;
            when 63 =>
                if index < 63 then
                    return COEF_63_ORDER(index);
                else
                    return (others => '0');
                end if;
            when others =>
                return (others => '0');
        end case;
    end function;
    
    -- �źŶ���
    signal data_shift_reg     : t_data_array(0 to FILTER_ORDER-1);
    signal upsample_counter   : integer range 0 to UPSAMPLE_RATE-1;
    signal filter_counter     : integer range 0 to FILTER_ORDER-1;
    signal processing_active  : std_logic;
    
    -- �˷�������ź�
    signal mult_data          : std_logic_vector(W_INPUT-1 downto 0);
    signal mult_coef          : std_logic_vector(W_COEF-1 downto 0);
    signal mult_result        : std_logic_vector(W_INPUT+W_COEF-1 downto 0);
    
    -- �ۼ����ź�
    signal accumulator        : std_logic_vector(W_ACCUMULATOR-1 downto 0);
    signal accumulator_valid  : std_logic;
    
    -- �������ź�
    signal output_data        : std_logic_vector(W_OUTPUT-1 downto 0);
    signal output_valid       : std_logic;
    signal output_ready       : std_logic;
    
    -- ��ˮ�߿����ź�
    signal pipeline_enable    : std_logic_vector(PIPELINE_STAGES-1 downto 0);
    signal pipeline_valid     : std_logic_vector(PIPELINE_STAGES-1 downto 0);
    
    -- ״̬�����Ͷ��壬�����˲���������4��״̬
    -- IDLE������״̬���ȴ���������
    -- LOADING�����ݼ���״̬����λ�Ĵ�����䣩
    -- PROCESSING���˲�����״̬���˼����㣩
    -- OUTPUT��������״̬
    type t_filter_state is (IDLE, LOADING, PROCESSING, OUTPUT);
    signal current_state      : t_filter_state;
    signal next_state         : t_filter_state;

begin

    -- �������
    ov_data <= output_data;
    o_data_valid <= output_valid and not i_bypass;
    o_data_ready <= output_ready;
    
    -- ��·ģʽ����
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            output_data <= (others => '0');
            output_valid <= '0';
        elsif rising_edge(i_clk) then
            if i_bypass = '1' then
                output_data <= iv_data;
                output_valid <= i_data_valid;
            end if;
        end if;
    end process;
    
    -- ״̬������
    process(i_clk, i_rst)
    begin
        if i_rst = '1' or i_reset_filter = '1' then
            current_state <= IDLE;
        elsif rising_edge(i_clk) then
            current_state <= next_state;
        end if;
    end process;
    
    -- ״̬ת���߼�
    process(current_state, i_data_valid, filter_counter, i_data_ready)
    begin
        case current_state is
            when IDLE =>
                if i_data_valid = '1' then
                    next_state <= LOADING;
                else
                    next_state <= IDLE;
                end if;
                
            when LOADING =>
                next_state <= PROCESSING;
                
            when PROCESSING =>
                if filter_counter = FILTER_ORDER-1 then
                    next_state <= OUTPUT;
                else
                    next_state <= PROCESSING;
                end if;
                
            when OUTPUT =>
                if i_data_ready = '1' then
                    next_state <= IDLE;
                else
                    next_state <= OUTPUT;
                end if;
                
            when others =>
                next_state <= IDLE;
        end case;
    end process;
    
    -- ������λ�Ĵ���
    process(i_clk, i_rst)
    begin
        if i_rst = '1' or i_reset_filter = '1' then
            data_shift_reg <= (others => (others => '0'));
        elsif rising_edge(i_clk) then
            if current_state = LOADING and i_data_valid = '1' then
                -- ��λ������������
                for i in FILTER_ORDER-1 downto 1 loop
                    data_shift_reg(i) <= data_shift_reg(i-1);
                end loop;
                data_shift_reg(0) <= iv_data;
            end if;
        end if;
    end process;
    
    -- �ϲ���������
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            upsample_counter <= 0;
        elsif rising_edge(i_clk) then
            if current_state = LOADING then
                upsample_counter <= (upsample_counter + 1) mod UPSAMPLE_RATE;
            end if;
        end if;
    end process;
    
    -- �˲������������
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            filter_counter <= 0;
        elsif rising_edge(i_clk) then
            if current_state = PROCESSING then
                if filter_counter = FILTER_ORDER-1 then
                    filter_counter <= 0;
                else
                    filter_counter <= filter_counter + 1;
                end if;
            else
                filter_counter <= 0;
            end if;
        end if;
    end process;
    
    -- �˷�������ѡ��
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            mult_data <= (others => '0');
            mult_coef <= (others => '0');
        elsif rising_edge(i_clk) then
            if current_state = PROCESSING then
                mult_data <= data_shift_reg(filter_counter);
                mult_coef <= get_filter_coef(FILTER_ORDER, filter_counter);
            end if;
        end if;
    end process;
    
    -- �˷���ʵ��
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            mult_result <= (others => '0');
        elsif rising_edge(i_clk) then
            -- �з��ų˷�
            mult_result <= std_logic_vector(signed(mult_data) * signed(mult_coef));
        end if;
    end process;
    
    -- �ۼ���
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            accumulator <= (others => '0');
            accumulator_valid <= '0';
        elsif rising_edge(i_clk) then
            if current_state = PROCESSING then
                if filter_counter = 0 then
                    -- ��ʼ�µ��ۼ�
                    accumulator <= std_logic_vector(resize(signed(mult_result), W_ACCUMULATOR));
                else
                    -- �����ۼ�
                    accumulator <= std_logic_vector(signed(accumulator) + signed(mult_result));
                end if;
                
                if filter_counter = FILTER_ORDER-1 then
                    accumulator_valid <= '1';
                else
                    accumulator_valid <= '0';
                end if;
            else
                accumulator_valid <= '0';
            end if;
        end if;
    end process;
    
    -- ������ݽ�λ������
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            output_data <= (others => '0');
            output_valid <= '0';
        elsif rising_edge(i_clk) then
            if accumulator_valid = '1' then
                output_data <= accumulator(W_ACCUMULATOR-1 downto W_ACCUMULATOR-W_OUTPUT);
                output_valid <= '1';
            else
                output_valid <= '0';
            end if;
        end if;
    end process;
    
    -- ׼�����ź�����
    output_ready <= '1' when current_state = IDLE else '0';

end Behavioral;