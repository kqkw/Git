library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity dvb_s2x_256apsk_decoder is
    Port (
        -- ʱ�Ӻ͸�λ
        clk             : in  STD_LOGIC;
        rst_n           : in  STD_LOGIC;
        
        -- �������ݽӿ�
        i_data          : in  STD_LOGIC_VECTOR(15 downto 0);  -- I·���ݣ�16λ�з���
        q_data          : in  STD_LOGIC_VECTOR(15 downto 0);  -- Q·���ݣ�16λ�з���
        data_valid      : in  STD_LOGIC;                      -- ����������Ч�ź�
        
        -- ����ӳ��ģʽ
        constellation_mode : in STD_LOGIC_VECTOR(1 downto 0);
        
        -- ����ӿ�
        decision_i      : out STD_LOGIC_VECTOR(15 downto 0);  -- �о���ʵ��
        decision_q      : out STD_LOGIC_VECTOR(15 downto 0);  -- �о����鲿
        symbol_bits     : out STD_LOGIC_VECTOR(7 downto 0);   -- 8λ�������
        output_valid    : out STD_LOGIC                       -- �����Ч�ź�
    );
end dvb_s2x_256apsk_decoder;

architecture Behavioral of dvb_s2x_256apsk_decoder is
    
    -- �������壺256APSK����ͼ���� (32+96+128����)
    constant RING1_RADIUS : integer := 16384;   -- �ڻ��뾶 (��һ����16λ)
    constant RING2_RADIUS : integer := 32768;   -- �л��뾶
    constant RING3_RADIUS : integer := 49152;   -- �⻷�뾶
    
    -- �����ĵ���
    constant RING1_POINTS : integer := 32;
    constant RING2_POINTS : integer := 96;
    constant RING3_POINTS : integer := 128;
    
    -- ��ˮ�߼Ĵ�������
    -- ��һ��������Ĵ���
    signal i_reg1, q_reg1 : signed(15 downto 0);
    signal valid_reg1 : STD_LOGIC;
    
    -- �ڶ��������ȼ���ͻ��о�
    signal i_reg2, q_reg2 : signed(15 downto 0);--�����ݴ������ I �� Q �������ӵ�һ�����洫����
    signal amplitude_sq : unsigned(31 downto 0);  -- ����ƽ�� I^2 + Q^2
    signal ring_sel : STD_LOGIC_VECTOR(1 downto 0);  -- ��ѡ�� 00:�ڻ� 01:�л� 10:�⻷
    signal valid_reg2 : STD_LOGIC;--�ڶ�����ˮ�ߵ�������Ч��־����ʾ��ǰ��һ���������Ƿ���Ч
    
    -- ����������λ����������о�
    signal i_reg3, q_reg3 : signed(15 downto 0);
    signal ring_sel_reg3 : STD_LOGIC_VECTOR(1 downto 0);--��ѡ���źţ���ʾ��ǰ����������һ�����ڻ����л����⻷��
    signal phase_sector : STD_LOGIC_VECTOR(7 downto 0);  -- ��λ����  ��ʾ��ǰ�����ź����ڵĽǶ��������  256 ��
    signal valid_reg3 : STD_LOGIC;
    
    -- ���ļ�������������ȷ��
    signal final_i, final_q : signed(15 downto 0);
    signal final_bits : STD_LOGIC_VECTOR(7 downto 0);--��ǰ�о�������ı�ţ�0~255��
    signal valid_reg4 : STD_LOGIC;
    
    -- ��������ұ����Ͷ���    ���� 256 ��Ԫ�ص�һά���飬��Ӧ 256APSK ������
    -- ÿ��Ԫ����һ�� 16 λ�з�������signed(15 downto 0)�������ڱ�ʾ I �� Q ����������ֵ  
    type constellation_lut_type is array (0 to 255) of signed(15 downto 0);
    
    -- ��������ұ�
    -- �ڻ�32�� + �л�96�� + �⻷128��
    function generate_constellation_i_lut return constellation_lut_type is
        variable lut : constellation_lut_type;
        variable angle : real;-- ��ǰ������ĽǶȣ���λ�����ȣ�
        variable radius : real;-- ��ǰ���İ뾶
    begin
        -- �ڻ�32�� (����0-31)
        for i in 0 to 31 loop
            angle := 2.0 * MATH_PI * real(i) / 32.0;
            radius := real(RING1_RADIUS);
            lut(i) := to_signed(integer(radius * cos(angle)), 16);
        end loop;
        
        -- �л�96�� (����32-127)
        for i in 0 to 95 loop
            angle := 2.0 * MATH_PI * real(i) / 96.0;
            radius := real(RING2_RADIUS);
            lut(i + 32) := to_signed(integer(radius * cos(angle)), 16);
        end loop;
        
        -- �⻷128�� (����128-255)
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
        -- �ڻ�32�� (����0-31)
        for i in 0 to 31 loop
            angle := 2.0 * MATH_PI * real(i) / 32.0;
            radius := real(RING1_RADIUS);
            lut(i) := to_signed(integer(radius * sin(angle)), 16);
        end loop;
        
        -- �л�96�� (����32-127)
        for i in 0 to 95 loop
            angle := 2.0 * MATH_PI * real(i) / 96.0;
            radius := real(RING2_RADIUS);
            lut(i + 32) := to_signed(integer(radius * sin(angle)), 16);
        end loop;
        
        -- �⻷128�� (����128-255)
        for i in 0 to 127 loop
            angle := 2.0 * MATH_PI * real(i) / 128.0;
            radius := real(RING3_RADIUS);
            lut(i + 128) := to_signed(integer(radius * sin(angle)), 16);
        end loop;
        
        return lut;
    end function;
    
    -- ��������ұ�
    constant CONSTELLATION_I_LUT : constellation_lut_type := generate_constellation_i_lut;
    constant CONSTELLATION_Q_LUT : constellation_lut_type := generate_constellation_q_lut;
    
    -- ��λ���㺯��
    function calculate_phase_sector(i_val, q_val : signed(15 downto 0); ring : STD_LOGIC_VECTOR(1 downto 0)) return STD_LOGIC_VECTOR is
        variable phase_index : integer;--���ռ���������������
        variable angle_rad : real;-- I/Q ת�������ĽǶ�ֵ����λ�ǻ��ȣ�
        variable sectors : integer;--��ǰ�����ж��ٸ�����
    begin
        -- ���ݻ�ѡ��ȷ��������
        case ring is
            when "00" => sectors := 32;   -- �ڻ�
            when "01" => sectors := 96;   -- �л�
            when "10" => sectors := 128;  -- �⻷
            when others => sectors := 32;
        end case;
        
        -- ��λ���� ����
        if i_val = 0 then
            if q_val > 0 then
                angle_rad := MATH_PI / 2.0;
            else
                angle_rad := -MATH_PI / 2.0;
            end if;
        else
            angle_rad := arctan(real(to_integer(q_val)) / real(to_integer(i_val)));
        end if;
        
        -- ��������
        if i_val < 0 then
            if q_val >= 0 then
                angle_rad := angle_rad + MATH_PI;
            else
                angle_rad := angle_rad - MATH_PI;
            end if;
        end if;
        
        -- ת��Ϊ���Ƕ�
        if angle_rad < 0.0 then
            angle_rad := angle_rad + 2.0 * MATH_PI;
        end if;
        
        -- ������������
        phase_index := integer(angle_rad / (2.0 * MATH_PI) * real(sectors));
        
        -- ȷ����������Ч��Χ��
        if phase_index >= sectors then
            phase_index := sectors - 1;
        end if;
        
        return STD_LOGIC_VECTOR(to_unsigned(phase_index, 8));
    end function;

begin

    -- ��ˮ�ߴ������
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            -- ��λ���мĴ���
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
            
            -- ��һ��������Ĵ���
            i_reg1 <= signed(i_data);
            q_reg1 <= signed(q_data);
            valid_reg1 <= data_valid;
            
            -- �ڶ��������ȼ���ͻ��о�
            i_reg2 <= i_reg1;
            q_reg2 <= q_reg1;
            valid_reg2 <= valid_reg1;
            
            if valid_reg1 = '1' then
                -- �������ƽ��
                amplitude_sq <= unsigned(i_reg1 * i_reg1) + unsigned(q_reg1 * q_reg1);
            end if;
            
            -- ���о������ڷ���ƽ����
            if amplitude_sq < to_unsigned(RING1_RADIUS * RING1_RADIUS * 2, 32) then
                ring_sel <= "00";  -- �ڻ�
            elsif amplitude_sq < to_unsigned(RING2_RADIUS * RING2_RADIUS * 2, 32) then
                ring_sel <= "01";  -- �л�
            else
                ring_sel <= "10";  -- �⻷
            end if;
            
            -- ����������λ����������о�
            i_reg3 <= i_reg2;
            q_reg3 <= q_reg2;
            ring_sel_reg3 <= ring_sel;
            valid_reg3 <= valid_reg2;
            
            if valid_reg2 = '1' then
                phase_sector <= calculate_phase_sector(i_reg2, q_reg2, ring_sel);
            end if;
            
            -- ���ļ�������������ȷ��
            valid_reg4 <= valid_reg3;
            
            if valid_reg3 = '1' then
                
                -- ���ݻ�ѡ�����λ����ȷ����������������
                case ring_sel_reg3 is
                    
                    when "00" =>  -- �ڻ� ƫ�� = 0
--                        final_i <= CONSTELLATION_I_LUT(to_integer(unsigned(phase_sector(4 downto 0))));
--                        final_q <= CONSTELLATION_Q_LUT(to_integer(unsigned(phase_sector(4 downto 0))));
--                        final_bits <= "000" & phase_sector(4 downto 0);
                        final_i <= CONSTELLATION_I_LUT(to_integer(unsigned(phase_sector(4 downto 0))));
                        final_q <= CONSTELLATION_Q_LUT(to_integer(unsigned(phase_sector(4 downto 0))));
                        final_bits <= std_logic_vector(to_unsigned(to_integer(unsigned(phase_sector(4 downto 0))) + 0, 8));
                        
                    when "01" =>  -- �л� ƫ�� = 32
--                        final_i <= CONSTELLATION_I_LUT(32 + to_integer(unsigned(phase_sector(6 downto 0))));
--                        final_q <= CONSTELLATION_Q_LUT(32 + to_integer(unsigned(phase_sector(6 downto 0))));
--                        final_bits <= "0" & phase_sector(6 downto 0);
                        final_i <= CONSTELLATION_I_LUT(32 + to_integer(unsigned(phase_sector(6 downto 0))));
                        final_q <= CONSTELLATION_Q_LUT(32 + to_integer(unsigned(phase_sector(6 downto 0))));
                        final_bits <= std_logic_vector(to_unsigned(to_integer(unsigned(phase_sector(6 downto 0))) + 32, 8));
                        
                    when "10" =>  -- �⻷ ƫ�� = 128
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

    -- �����ֵ
    decision_i <= STD_LOGIC_VECTOR(final_i);
    decision_q <= STD_LOGIC_VECTOR(final_q);
    symbol_bits <= final_bits;
    output_valid <= valid_reg4;

end Behavioral;
