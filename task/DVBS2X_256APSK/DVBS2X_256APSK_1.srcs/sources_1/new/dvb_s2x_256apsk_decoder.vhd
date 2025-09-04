library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity dvb_s2x_256apsk_decoder is
    Port (
        -- 时钟和复位
        clk             : in  STD_LOGIC;
        rst_n           : in  STD_LOGIC;
        
        -- 输入数据接口
        i_data          : in  STD_LOGIC_VECTOR(15 downto 0);  -- I路数据，16位有符号
        q_data          : in  STD_LOGIC_VECTOR(15 downto 0);  -- Q路数据，16位有符号
        data_valid      : in  STD_LOGIC;                      -- 输入数据有效信号
        
        -- 星座映射模式
        constellation_mode : in STD_LOGIC_VECTOR(1 downto 0);
        
        -- 输出接口
        decision_i      : out STD_LOGIC_VECTOR(15 downto 0);  -- 判决后实部
        decision_q      : out STD_LOGIC_VECTOR(15 downto 0);  -- 判决后虚部
        symbol_bits     : out STD_LOGIC_VECTOR(7 downto 0);   -- 8位符号输出
        output_valid    : out STD_LOGIC                       -- 输出有效信号
    );
end dvb_s2x_256apsk_decoder;

architecture Behavioral of dvb_s2x_256apsk_decoder is
    
    -- 常量定义：256APSK星座图参数 (32+96+128配置)
    constant RING1_RADIUS : integer := 16384;   -- 内环半径 (归一化到16位)
    constant RING2_RADIUS : integer := 32768;   -- 中环半径
    constant RING3_RADIUS : integer := 49152;   -- 外环半径
    
    -- 各环的点数
    constant RING1_POINTS : integer := 32;
    constant RING2_POINTS : integer := 96;
    constant RING3_POINTS : integer := 128;
    
    -- 流水线寄存器定义
    -- 第一级：输入寄存器
    signal i_reg1, q_reg1 : signed(15 downto 0);
    signal valid_reg1 : STD_LOGIC;
    
    -- 第二级：幅度计算和环判决
    signal i_reg2, q_reg2 : signed(15 downto 0);--用于暂存输入的 I 和 Q 分量（从第一级锁存传来）
    signal amplitude_sq : unsigned(31 downto 0);  -- 幅度平方 I^2 + Q^2
    signal ring_sel : STD_LOGIC_VECTOR(1 downto 0);  -- 环选择 00:内环 01:中环 10:外环
    signal valid_reg2 : STD_LOGIC;--第二级流水线的数据有效标志，表示当前这一级的数据是否有效
    
    -- 第三级：相位计算和扇区判决
    signal i_reg3, q_reg3 : signed(15 downto 0);
    signal ring_sel_reg3 : STD_LOGIC_VECTOR(1 downto 0);--环选择信号，表示当前输入属于哪一环（内环、中环或外环）
    signal phase_sector : STD_LOGIC_VECTOR(7 downto 0);  -- 相位扇区  表示当前输入信号所在的角度扇区编号  256 个
    signal valid_reg3 : STD_LOGIC;
    
    -- 第四级：最终星座点确定
    signal final_i, final_q : signed(15 downto 0);
    signal final_bits : STD_LOGIC_VECTOR(7 downto 0);--当前判决星座点的编号（0~255）
    signal valid_reg4 : STD_LOGIC;
    
    -- 星座点查找表类型定义    包含 256 个元素的一维数组，对应 256APSK 星座点
    -- 每个元素是一个 16 位有符号数（signed(15 downto 0)），用于表示 I 或 Q 分量的坐标值  
    type constellation_lut_type is array (0 to 255) of signed(15 downto 0);
    
    -- 星座点查找表
    -- 内环32点 + 中环96点 + 外环128点
    function generate_constellation_i_lut return constellation_lut_type is
        variable lut : constellation_lut_type;
        variable angle : real;-- 当前星座点的角度（单位：弧度）
        variable radius : real;-- 当前环的半径
    begin
        -- 内环32点 (索引0-31)
        for i in 0 to 31 loop
            angle := 2.0 * MATH_PI * real(i) / 32.0;
            radius := real(RING1_RADIUS);
            lut(i) := to_signed(integer(radius * cos(angle)), 16);
        end loop;
        
        -- 中环96点 (索引32-127)
        for i in 0 to 95 loop
            angle := 2.0 * MATH_PI * real(i) / 96.0;
            radius := real(RING2_RADIUS);
            lut(i + 32) := to_signed(integer(radius * cos(angle)), 16);
        end loop;
        
        -- 外环128点 (索引128-255)
        for i in 0 to 127 loop
            angle := 2.0 * MATH_PI * real(i) / 128.0;
            radius := real(RING3_RADIUS);
            lut(i + 128) := to_signed(integer(radius * cos(angle)), 16);
        end loop;
        
        return lut;
    end function;
    
    function generate_constellation_q_lut return constellation_lut_type is
        variable lut : constellation_lut_type;
        variable angle : real;
        variable radius : real;
    begin
        -- 内环32点 (索引0-31)
        for i in 0 to 31 loop
            angle := 2.0 * MATH_PI * real(i) / 32.0;
            radius := real(RING1_RADIUS);
            lut(i) := to_signed(integer(radius * sin(angle)), 16);
        end loop;
        
        -- 中环96点 (索引32-127)
        for i in 0 to 95 loop
            angle := 2.0 * MATH_PI * real(i) / 96.0;
            radius := real(RING2_RADIUS);
            lut(i + 32) := to_signed(integer(radius * sin(angle)), 16);
        end loop;
        
        -- 外环128点 (索引128-255)
        for i in 0 to 127 loop
            angle := 2.0 * MATH_PI * real(i) / 128.0;
            radius := real(RING3_RADIUS);
            lut(i + 128) := to_signed(integer(radius * sin(angle)), 16);
        end loop;
        
        return lut;
    end function;
    
    -- 星座点查找表
    constant CONSTELLATION_I_LUT : constellation_lut_type := generate_constellation_i_lut;
    constant CONSTELLATION_Q_LUT : constellation_lut_type := generate_constellation_q_lut;
    
    -- 相位计算函数
    function calculate_phase_sector(i_val, q_val : signed(15 downto 0); ring : STD_LOGIC_VECTOR(1 downto 0)) return STD_LOGIC_VECTOR is
        variable phase_index : integer;--最终计算出来的扇区编号
        variable angle_rad : real;-- I/Q 转换出来的角度值（单位是弧度）
        variable sectors : integer;--当前环上有多少个扇区
    begin
        -- 根据环选择确定扇区数
        case ring is
            when "00" => sectors := 32;   -- 内环
            when "01" => sectors := 96;   -- 中环
            when "10" => sectors := 128;  -- 外环
            when others => sectors := 32;
        end case;
        
        -- 相位计算 弧度
        if i_val = 0 then
            if q_val > 0 then
                angle_rad := MATH_PI / 2.0;
            else
                angle_rad := -MATH_PI / 2.0;
            end if;
        else
            angle_rad := arctan(real(to_integer(q_val)) / real(to_integer(i_val)));
        end if;
        
        -- 处理象限
        if i_val < 0 then
            if q_val >= 0 then
                angle_rad := angle_rad + MATH_PI;
            else
                angle_rad := angle_rad - MATH_PI;
            end if;
        end if;
        
        -- 转换为正角度
        if angle_rad < 0.0 then
            angle_rad := angle_rad + 2.0 * MATH_PI;
        end if;
        
        -- 计算扇区索引
        phase_index := integer(angle_rad / (2.0 * MATH_PI) * real(sectors));
        
        -- 确保索引在有效范围内
        if phase_index >= sectors then
            phase_index := sectors - 1;
        end if;
        
        return STD_LOGIC_VECTOR(to_unsigned(phase_index, 8));
    end function;

begin

    -- 流水线处理过程
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            -- 复位所有寄存器
            i_reg1 <= (others => '0');
            q_reg1 <= (others => '0');
            valid_reg1 <= '0';
            
            i_reg2 <= (others => '0');
            q_reg2 <= (others => '0');
            amplitude_sq <= (others => '0');
            ring_sel <= "00";
            valid_reg2 <= '0';
            
            i_reg3 <= (others => '0');
            q_reg3 <= (others => '0');
            ring_sel_reg3 <= "00";
            phase_sector <= (others => '0');
            valid_reg3 <= '0';
            
            final_i <= (others => '0');
            final_q <= (others => '0');
            final_bits <= (others => '0');
            valid_reg4 <= '0';
            
        elsif rising_edge(clk) then
            
            -- 第一级：输入寄存器
            i_reg1 <= signed(i_data);
            q_reg1 <= signed(q_data);
            valid_reg1 <= data_valid;
            
            -- 第二级：幅度计算和环判决
            i_reg2 <= i_reg1;
            q_reg2 <= q_reg1;
            valid_reg2 <= valid_reg1;
            
            if valid_reg1 = '1' then
                -- 计算幅度平方
                amplitude_sq <= unsigned(i_reg1 * i_reg1) + unsigned(q_reg1 * q_reg1);
            end if;
            
            -- 环判决（基于幅度平方）
            if amplitude_sq < to_unsigned(RING1_RADIUS * RING1_RADIUS * 2, 32) then
                ring_sel <= "00";  -- 内环
            elsif amplitude_sq < to_unsigned(RING2_RADIUS * RING2_RADIUS * 2, 32) then
                ring_sel <= "01";  -- 中环
            else
                ring_sel <= "10";  -- 外环
            end if;
            
            -- 第三级：相位计算和扇区判决
            i_reg3 <= i_reg2;
            q_reg3 <= q_reg2;
            ring_sel_reg3 <= ring_sel;
            valid_reg3 <= valid_reg2;
            
            if valid_reg2 = '1' then
                phase_sector <= calculate_phase_sector(i_reg2, q_reg2, ring_sel);
            end if;
            
            -- 第四级：最终星座点确定
            valid_reg4 <= valid_reg3;
            
            if valid_reg3 = '1' then
                
                -- 根据环选择和相位扇区确定最终星座点索引
                case ring_sel_reg3 is
                    
                    when "00" =>  -- 内环 偏移 = 0
--                        final_i <= CONSTELLATION_I_LUT(to_integer(unsigned(phase_sector(4 downto 0))));
--                        final_q <= CONSTELLATION_Q_LUT(to_integer(unsigned(phase_sector(4 downto 0))));
--                        final_bits <= "000" & phase_sector(4 downto 0);
                        final_i <= CONSTELLATION_I_LUT(to_integer(unsigned(phase_sector(4 downto 0))));
                        final_q <= CONSTELLATION_Q_LUT(to_integer(unsigned(phase_sector(4 downto 0))));
                        final_bits <= std_logic_vector(to_unsigned(to_integer(unsigned(phase_sector(4 downto 0))) + 0, 8));
                        
                    when "01" =>  -- 中环 偏移 = 32
--                        final_i <= CONSTELLATION_I_LUT(32 + to_integer(unsigned(phase_sector(6 downto 0))));
--                        final_q <= CONSTELLATION_Q_LUT(32 + to_integer(unsigned(phase_sector(6 downto 0))));
--                        final_bits <= "0" & phase_sector(6 downto 0);
                        final_i <= CONSTELLATION_I_LUT(32 + to_integer(unsigned(phase_sector(6 downto 0))));
                        final_q <= CONSTELLATION_Q_LUT(32 + to_integer(unsigned(phase_sector(6 downto 0))));
                        final_bits <= std_logic_vector(to_unsigned(to_integer(unsigned(phase_sector(6 downto 0))) + 32, 8));
                        
                    when "10" =>  -- 外环 偏移 = 128
--                        final_i <= CONSTELLATION_I_LUT(128 + to_integer(unsigned(phase_sector(6 downto 0))));
--                        final_q <= CONSTELLATION_Q_LUT(128 + to_integer(unsigned(phase_sector(6 downto 0))));
--                        final_bits <= phase_sector(7 downto 0);
                        final_i <= CONSTELLATION_I_LUT(128 + to_integer(unsigned(phase_sector(6 downto 0))));
                        final_q <= CONSTELLATION_Q_LUT(128 + to_integer(unsigned(phase_sector(6 downto 0))));
                        final_bits <= std_logic_vector(to_unsigned(to_integer(unsigned(phase_sector(6 downto 0))) + 128, 8));
                        
                    when others =>
                        final_i <= (others => '0');
                        final_q <= (others => '0');
                        final_bits <= (others => '0');
                    
                end case;
            end if;
            
        end if;
    end process;

    -- 输出赋值
    decision_i <= STD_LOGIC_VECTOR(final_i);
    decision_q <= STD_LOGIC_VECTOR(final_q);
    symbol_bits <= final_bits;
    output_valid <= valid_reg4;

end Behavioral;
