library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity tb_dvb_s2x_256apsk_decoder is
end tb_dvb_s2x_256apsk_decoder;

architecture Behavioral of tb_dvb_s2x_256apsk_decoder is

    -- ������ģ������
    component dvb_s2x_256apsk_decoder
        Port (
            clk             : in  STD_LOGIC;
            rst_n           : in  STD_LOGIC;
            i_data          : in  STD_LOGIC_VECTOR(15 downto 0);
            q_data          : in  STD_LOGIC_VECTOR(15 downto 0);
            data_valid      : in  STD_LOGIC;
            constellation_mode : in STD_LOGIC_VECTOR(1 downto 0);
            decision_i      : out STD_LOGIC_VECTOR(15 downto 0);--������о����
            decision_q      : out STD_LOGIC_VECTOR(15 downto 0);
            symbol_bits     : out STD_LOGIC_VECTOR(7 downto 0);--�������������
            output_valid    : out STD_LOGIC
        );
    end component;

    -- ʱ�Ӻ͸�λ�ź�
    signal clk : STD_LOGIC := '0';
    signal rst_n : STD_LOGIC := '0';
    
    -- �����ź�
    signal i_data : STD_LOGIC_VECTOR(15 downto 0) := (others => '0');--i_data = "0000_0000_0000_0000"
    signal q_data : STD_LOGIC_VECTOR(15 downto 0) := (others => '0');
    signal data_valid : STD_LOGIC := '0';
    signal constellation_mode : STD_LOGIC_VECTOR(1 downto 0) := "00";
    
    -- ����ź�
    signal decision_i : STD_LOGIC_VECTOR(15 downto 0);
    signal decision_q : STD_LOGIC_VECTOR(15 downto 0);
    signal symbol_bits : STD_LOGIC_VECTOR(7 downto 0);
    signal output_valid : STD_LOGIC;
    
    -- ʱ�����ڳ��� (200MHz = 5ns)
    constant CLK_PERIOD : time := 5 ns;
    
    -- �����������Ͷ���
    type test_vector_type is record
        i_val : integer;
        q_val : integer;
        expected_ring : integer;  -- �����Ļ���0=�ڻ�, 1=�л�, 2=�⻷
        description : string(1 to 20);--�Բ��������ļ������
    end record;
    
    -- ������������  ������Χ���������Ȼ����Χ�� 0 �� N��
    type test_vector_array is array (natural range <>) of test_vector_type;
    
--    -- Ԥ�����������
--    constant TEST_VECTORS : test_vector_array := (
--        -- �ڻ��������� (С����)
--        (16384, 0, 0, "Inner ring 0 deg   "),      -- �ڻ���0�ȷ���
--        (11585, 11585, 0, "Inner ring 45 deg  "),  -- �ڻ���45�ȷ���
--        (0, 16384, 0, "Inner ring 90 deg  "),      -- �ڻ���90�ȷ���
--        (-11585, 11585, 0, "Inner ring 135 deg "), -- �ڻ���135�ȷ���
--        (-16384, 0, 0, "Inner ring 180 deg "),     -- �ڻ���180�ȷ���
        
--        -- �л��������� (�еȷ���)
--        (32768, 0, 1, "Mid ring 0 deg     "),      -- �л���0�ȷ���
--        (23170, 23170, 1, "Mid ring 45 deg    "),  -- �л���45�ȷ���
--        (0, 32768, 1, "Mid ring 90 deg    "),      -- �л���90�ȷ���
--        (-23170, 23170, 1, "Mid ring 135 deg   "), -- �л���135�ȷ���
--        (-32768, 0, 1, "Mid ring 180 deg   "),     -- �л���180�ȷ���
        
--        -- �⻷�������� (�����)
--        (49152, 0, 2, "Outer ring 0 deg   "),      -- �⻷��0�ȷ���
--        (34755, 34755, 2, "Outer ring 45 deg  "),  -- �⻷��45�ȷ���
--        (0, 49152, 2, "Outer ring 90 deg  "),      -- �⻷��90�ȷ���
--        (-34755, 34755, 2, "Outer ring 135 deg "), -- �⻷��135�ȷ���
--        (-49152, 0, 2, "Outer ring 180 deg "),     -- �⻷��180�ȷ���
        
--        -- �߽��������
--        (20000, 0, 0, "Boundary test 1    "),      -- �߽����
--        (40000, 0, 1, "Boundary test 2    "),      -- �߽����
--        (60000, 0, 2, "Boundary test 3    ")       -- �߽����
--    );
    -- Ԥ�����������
    constant TEST_VECTORS : test_vector_array := (
--        (-23170, 23170, 1, "Mid ring 135 deg   "), -- �л���135�ȷ���
        (-34755, 34755, 2, "Outer ring 135 deg "), -- �⻷��135�ȷ���

        -- �߽��������
        (60000, 0, 2, "Boundary test 3    ")       -- �߽����
    );
    
    -- ��������ź�
    signal sim_end : boolean := false;
    signal test_index : integer := 0;

begin

    -- ʵ����������ģ��
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

    -- ʱ������
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

    -- ���������
    stim_process: process
        variable expected_i, expected_q : integer;--Ԥ�ڵ��о����ʵ�����鲿
        variable actual_i, actual_q : integer;--��ģ�������ȡ����ʵ���о����
        variable error_i, error_q : integer;--����ʵ�������Ԥ�����֮������
        variable error_threshold : integer := 5000;  -- �����ֵ
        
        -- ������������ĺ���
        function calculate_expected_output(i_val, q_val : integer; ring : integer) return integer is
            variable angle : real;--�źŵ���λ��
            variable sectors : integer;
            variable phase_index : integer;
        begin
            -- ���ݻ�ѡ��ȷ��������
            case ring is
                when 0 => sectors := 32;   -- �ڻ�
                when 1 => sectors := 96;   -- �л�
                when 2 => sectors := 128;  -- �⻷
                when others => sectors := 32;
            end case;
            
            -- ������λ��
            if i_val = 0 then
                if q_val > 0 then
                    angle := MATH_PI / 2.0;
                else
                    angle := -MATH_PI / 2.0;
                end if;
            else
                angle := arctan(real(q_val) / real(i_val));
            end if;
            
            -- ��������
            if i_val < 0 then
                if q_val >= 0 then
                    angle := angle + MATH_PI;
                else
                    angle := angle - MATH_PI;
                end if;
            end if;
            
            -- ת��Ϊ���Ƕ�
            if angle < 0.0 then
                angle := angle + 2.0 * MATH_PI;
            end if;
            
            -- ������������
            phase_index := integer(angle / (2.0 * MATH_PI) * real(sectors));
            
            -- ȷ����������Ч��Χ��
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
        -- ��ʼ��
        rst_n <= '0';
        data_valid <= '0';
        i_data <= (others => '0');
        q_data <= (others => '0');
        constellation_mode <= "00";
        
        -- ������濪ʼ��Ϣ
        report "========================================";
        report "DVB-S2X 256APSK Ӳ�о�ģ����濪ʼ";
        report "ʱ��Ƶ��: 200MHz (����: 5ns)";
        report "������������: " & integer'image(TEST_VECTORS'length);
        report "========================================";
        
        -- �ȴ�����ʱ������
        wait for CLK_PERIOD * 10;
        
        -- �ͷŸ�λ
        rst_n <= '1';
        wait for CLK_PERIOD * 5;
        
        -- �������в�������
        for i in TEST_VECTORS'range loop
            test_index <= i;
            
            -- �����ǰ������Ϣ
            report "���� " & integer'image(i+1) & ": " & TEST_VECTORS(i).description;
            report "  ����: I=" & integer'image(TEST_VECTORS(i).i_val) & 
                   ", Q=" & integer'image(TEST_VECTORS(i).q_val) & 
                   ", ������=" & integer'image(TEST_VECTORS(i).expected_ring);
            
            -- ������������
            i_data <= STD_LOGIC_VECTOR(to_signed(TEST_VECTORS(i).i_val, 16));
            q_data <= STD_LOGIC_VECTOR(to_signed(TEST_VECTORS(i).q_val, 16));
            data_valid <= '1';
            
            -- �ȴ�һ��ʱ������
            wait for CLK_PERIOD;
            
            -- �ر�������Ч�ź�
            data_valid <= '0';
            
            -- �ȴ���ˮ�ߴ������ (4����ˮ��)
--            wait for CLK_PERIOD * 5;
            
--            -- ��������Ч�ź�
--            if output_valid = '1' then
--                -- ��ȡʵ�����ֵ
--                actual_i := to_integer(signed(decision_i));
--                actual_q := to_integer(signed(decision_q));
                
--                -- �������
--                error_i := abs(actual_i - TEST_VECTORS(i).i_val);
--                error_q := abs(actual_q - TEST_VECTORS(i).q_val);
                
--                -- ������
--                report "  ���: I=" & integer'image(actual_i) & 
--                       ", Q=" & integer'image(actual_q) & 
--                       ", ����λ=" & integer'image(to_integer(unsigned(symbol_bits)));
--                report "  ���: I_err=" & integer'image(error_i) & 
--                       ", Q_err=" & integer'image(error_q);
                
--            else
--                report "  ����: �����Ч�ź�δ����!" severity error;
--            end if;
            
            
            -- ����֮��ļ��
            wait for CLK_PERIOD * 3;
            
        end loop;
        
    end process;


end Behavioral;