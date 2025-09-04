library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity tb_dvb_s2x_256apsk_decoder is
end tb_dvb_s2x_256apsk_decoder;

architecture Behavioral of tb_dvb_s2x_256apsk_decoder is

    -- 待测试模块声明
    component dvb_s2x_256apsk_decoder
        Port (
            clk             : in  STD_LOGIC;
            rst_n           : in  STD_LOGIC;
            i_data          : in  STD_LOGIC_VECTOR(15 downto 0);
            q_data          : in  STD_LOGIC_VECTOR(15 downto 0);
            data_valid      : in  STD_LOGIC;
            constellation_mode : in STD_LOGIC_VECTOR(1 downto 0);
            decision_i      : out STD_LOGIC_VECTOR(15 downto 0);--输出的判决结果
            decision_q      : out STD_LOGIC_VECTOR(15 downto 0);
            symbol_bits     : out STD_LOGIC_VECTOR(7 downto 0);--输出的星座点编号
            output_valid    : out STD_LOGIC
        );
    end component;

    -- 时钟和复位信号
    signal clk : STD_LOGIC := '0';
    signal rst_n : STD_LOGIC := '0';
    
    -- 输入信号
    signal i_data : STD_LOGIC_VECTOR(15 downto 0) := (others => '0');--i_data = "0000_0000_0000_0000"
    signal q_data : STD_LOGIC_VECTOR(15 downto 0) := (others => '0');
    signal data_valid : STD_LOGIC := '0';
    signal constellation_mode : STD_LOGIC_VECTOR(1 downto 0) := "00";
    
    -- 输出信号
    signal decision_i : STD_LOGIC_VECTOR(15 downto 0);
    signal decision_q : STD_LOGIC_VECTOR(15 downto 0);
    signal symbol_bits : STD_LOGIC_VECTOR(7 downto 0);
    signal output_valid : STD_LOGIC;
    
    -- 时钟周期常量 (200MHz = 5ns)
    constant CLK_PERIOD : time := 5 ns;
    
    -- 测试数据类型定义
    type test_vector_type is record
        i_val : integer;
        q_val : integer;
        expected_ring : integer;  -- 期望的环：0=内环, 1=中环, 2=外环
        description : string(1 to 20);--对测试样例的简短描述
    end record;
    
    -- 测试向量数组  索引范围是任意的自然数范围（ 0 到 N）
    type test_vector_array is array (natural range <>) of test_vector_type;
    
--    -- 预定义测试向量
--    constant TEST_VECTORS : test_vector_array := (
--        -- 内环测试数据 (小幅度)
--        (16384, 0, 0, "Inner ring 0 deg   "),      -- 内环，0度方向
--        (11585, 11585, 0, "Inner ring 45 deg  "),  -- 内环，45度方向
--        (0, 16384, 0, "Inner ring 90 deg  "),      -- 内环，90度方向
--        (-11585, 11585, 0, "Inner ring 135 deg "), -- 内环，135度方向
--        (-16384, 0, 0, "Inner ring 180 deg "),     -- 内环，180度方向
        
--        -- 中环测试数据 (中等幅度)
--        (32768, 0, 1, "Mid ring 0 deg     "),      -- 中环，0度方向
--        (23170, 23170, 1, "Mid ring 45 deg    "),  -- 中环，45度方向
--        (0, 32768, 1, "Mid ring 90 deg    "),      -- 中环，90度方向
--        (-23170, 23170, 1, "Mid ring 135 deg   "), -- 中环，135度方向
--        (-32768, 0, 1, "Mid ring 180 deg   "),     -- 中环，180度方向
        
--        -- 外环测试数据 (大幅度)
--        (49152, 0, 2, "Outer ring 0 deg   "),      -- 外环，0度方向
--        (34755, 34755, 2, "Outer ring 45 deg  "),  -- 外环，45度方向
--        (0, 49152, 2, "Outer ring 90 deg  "),      -- 外环，90度方向
--        (-34755, 34755, 2, "Outer ring 135 deg "), -- 外环，135度方向
--        (-49152, 0, 2, "Outer ring 180 deg "),     -- 外环，180度方向
        
--        -- 边界测试数据
--        (20000, 0, 0, "Boundary test 1    "),      -- 边界测试
--        (40000, 0, 1, "Boundary test 2    "),      -- 边界测试
--        (60000, 0, 2, "Boundary test 3    ")       -- 边界测试
--    );
    -- 预定义测试向量
    constant TEST_VECTORS : test_vector_array := (
--        (-23170, 23170, 1, "Mid ring 135 deg   "), -- 中环，135度方向
        (-34755, 34755, 2, "Outer ring 135 deg "), -- 外环，135度方向

        -- 边界测试数据
        (60000, 0, 2, "Boundary test 3    ")       -- 边界测试
    );
    
    -- 仿真控制信号
    signal sim_end : boolean := false;
    signal test_index : integer := 0;

begin

    -- 实例化待测试模块
    uut: dvb_s2x_256apsk_decoder
        Port map (
            clk => clk,
            rst_n => rst_n,
            i_data => i_data,
            q_data => q_data,
            data_valid => data_valid,
            constellation_mode => constellation_mode,
            decision_i => decision_i,
            decision_q => decision_q,
            symbol_bits => symbol_bits,
            output_valid => output_valid
        );

    -- 时钟生成
    clk_process: process
    begin
        while not sim_end loop
            clk <= '0';
            wait for CLK_PERIOD/2;
            clk <= '1';
            wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;

    -- 主仿真进程
    stim_process: process
        variable expected_i, expected_q : integer;--预期的判决结果实部和虚部
        variable actual_i, actual_q : integer;--从模块输出读取到的实际判决结果
        variable error_i, error_q : integer;--计算实际输出与预期输出之间的误差
        variable error_threshold : integer := 5000;  -- 误差阈值
        
        -- 计算期望输出的函数
        function calculate_expected_output(i_val, q_val : integer; ring : integer) return integer is
            variable angle : real;--信号的相位角
            variable sectors : integer;
            variable phase_index : integer;
        begin
            -- 根据环选择确定扇区数
            case ring is
                when 0 => sectors := 32;   -- 内环
                when 1 => sectors := 96;   -- 中环
                when 2 => sectors := 128;  -- 外环
                when others => sectors := 32;
            end case;
            
            -- 计算相位角
            if i_val = 0 then
                if q_val > 0 then
                    angle := MATH_PI / 2.0;
                else
                    angle := -MATH_PI / 2.0;
                end if;
            else
                angle := arctan(real(q_val) / real(i_val));
            end if;
            
            -- 处理象限
            if i_val < 0 then
                if q_val >= 0 then
                    angle := angle + MATH_PI;
                else
                    angle := angle - MATH_PI;
                end if;
            end if;
            
            -- 转换为正角度
            if angle < 0.0 then
                angle := angle + 2.0 * MATH_PI;
            end if;
            
            -- 计算扇区索引
            phase_index := integer(angle / (2.0 * MATH_PI) * real(sectors));
            
            -- 确保索引在有效范围内
            if phase_index >= sectors then
                phase_index := sectors - 1;
            end if;
            
            case ring is  
                when 0 => return phase_index; 
                when 1 => return 32 + phase_index;
                when 2 => return 128 + phase_index; 
                when others => return 0;
            end case;
        end function;
        
    begin
        -- 初始化
        rst_n <= '0';
        data_valid <= '0';
        i_data <= (others => '0');
        q_data <= (others => '0');
        constellation_mode <= "00";
        
        -- 输出仿真开始信息
        report "========================================";
        report "DVB-S2X 256APSK 硬判决模块仿真开始";
        report "时钟频率: 200MHz (周期: 5ns)";
        report "测试向量数量: " & integer'image(TEST_VECTORS'length);
        report "========================================";
        
        -- 等待几个时钟周期
        wait for CLK_PERIOD * 10;
        
        -- 释放复位
        rst_n <= '1';
        wait for CLK_PERIOD * 5;
        
        -- 遍历所有测试向量
        for i in TEST_VECTORS'range loop
            test_index <= i;
            
            -- 输出当前测试信息
            report "测试 " & integer'image(i+1) & ": " & TEST_VECTORS(i).description;
            report "  输入: I=" & integer'image(TEST_VECTORS(i).i_val) & 
                   ", Q=" & integer'image(TEST_VECTORS(i).q_val) & 
                   ", 期望环=" & integer'image(TEST_VECTORS(i).expected_ring);
            
            -- 设置输入数据
            i_data <= STD_LOGIC_VECTOR(to_signed(TEST_VECTORS(i).i_val, 16));
            q_data <= STD_LOGIC_VECTOR(to_signed(TEST_VECTORS(i).q_val, 16));
            data_valid <= '1';
            
            -- 等待一个时钟周期
            wait for CLK_PERIOD;
            
            -- 关闭数据有效信号
            data_valid <= '0';
            
            -- 等待流水线处理完成 (4级流水线)
--            wait for CLK_PERIOD * 5;
            
--            -- 检查输出有效信号
--            if output_valid = '1' then
--                -- 获取实际输出值
--                actual_i := to_integer(signed(decision_i));
--                actual_q := to_integer(signed(decision_q));
                
--                -- 计算误差
--                error_i := abs(actual_i - TEST_VECTORS(i).i_val);
--                error_q := abs(actual_q - TEST_VECTORS(i).q_val);
                
--                -- 输出结果
--                report "  输出: I=" & integer'image(actual_i) & 
--                       ", Q=" & integer'image(actual_q) & 
--                       ", 符号位=" & integer'image(to_integer(unsigned(symbol_bits)));
--                report "  误差: I_err=" & integer'image(error_i) & 
--                       ", Q_err=" & integer'image(error_q);
                
--            else
--                report "  错误: 输出无效信号未激活!" severity error;
--            end if;
            
            
            -- 测试之间的间隔
            wait for CLK_PERIOD * 3;
            
        end loop;
        
    end process;


end Behavioral;