library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;
use IEEE.NUMERIC_STD.all;

entity tb_Musig_uplink_tx_module_signaling_srrc is
end tb_Musig_uplink_tx_module_signaling_srrc;

architecture Behavioral of tb_Musig_uplink_tx_module_signaling_srrc is

    -- 组件声明
    component Musig_uplink_tx_module_signaling_srrc
        generic (
            W_in      : integer := 12;
            W_filter  : integer := 16;
            L_filter  : integer := 15;
            L_multOut : integer := 18
        );
        port ( 
            i_clk     : in  std_logic;
            i_rst     : in  std_logic;
            iv_data   : in  std_logic_vector(W_in-1 downto 0);
            i_en      : in  std_logic;
            ov_data   : out std_logic_vector(W_in-1 downto 0);
            o_data_en : out std_logic
        );
    end component;

    -- 测试信号
    signal clk      : std_logic := '0';
    signal rst      : std_logic := '1';
    signal data_in  : std_logic_vector(11 downto 0) := (others => '0');
    signal en       : std_logic := '0';
    signal data_out : std_logic_vector(11 downto 0);
    signal data_en  : std_logic;
    
    -- 时钟周期定义
    constant clk_period : time := 10 ns;  -- 100MHz时钟

begin

    -- 实例化被测单元
    uut: Musig_uplink_tx_module_signaling_srrc
        port map (
            i_clk     => clk,
            i_rst     => rst,
            iv_data   => data_in,
            i_en      => en,
            ov_data   => data_out,
            o_data_en => data_en
        );

    -- 时钟生成
    clk_process: process
    begin
        clk <= '0';
        wait for clk_period/2;
        clk <= '1';
        wait for clk_period/2;
    end process;

    -- 测试激励
    stim_proc: process
    begin
        -- 初始化复位
        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        wait for clk_period*2;
        
        -- 测试1: 验证最小输入值(0x800)
        data_in <= "100000000000";  
        en <= '1';
        wait for clk_period;
        en <= '0';
        
        -- 等待滤波器处理完成
        wait until data_en = '1';
        wait for clk_period;

        
        -- 测试2: 验证最大输入值(0x7FF)
        data_in <= "011111111111";  
        en <= '1';
        wait for clk_period;
        en <= '0';
        
        wait until data_en = '1';
        wait for clk_period;
        
        
        -- 测试3: 0x000
        data_in <= "000000000000"; 
        en <= '1';
        wait for clk_period;
        en <= '0';
        
        wait until data_en = '1';
        wait for clk_period;
        

        
        -- 测试4: 
        data_in <= "111111111111";  
        en <= '1';
        wait for clk_period;
        en <= '0';
        wait until data_en = '1';
        wait for clk_period;
        

        

    end process;

end Behavioral;





