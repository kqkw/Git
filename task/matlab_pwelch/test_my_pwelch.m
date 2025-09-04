function test_my_pwelch()
    % 生成测试信号
    fs = 1000;              % 采样频率
    t = 0:1/fs:1-1/fs;      % 时间向量
    f1 = 50; f2 = 150;      % 两个频率分量
    
    % 创建包含两个正弦波和噪声的信号
    x = sin(2*pi*f1*t) + 0.5*sin(2*pi*f2*t) + 0.2*randn(size(t));
    
    % 使用自实现的pwelch
    [Pxx_my, f_my] = my_pwelch(x, [], [], [], fs);
    
    % 使用MATLAB内置pwelch进行对比
    [Pxx_matlab, f_matlab] = pwelch(x, [], [], [], fs);
    
    % 绘制对比图
    figure;
    subplot(2,1,1);
    plot(t(1:500), x(1:500));
    title('测试信号（前0.5秒）');
    xlabel('时间 (秒)');
    ylabel('幅度');
    grid on;
    
    subplot(2,1,2);
    semilogy(f_my, Pxx_my, 'r-', 'LineWidth', 2);
    hold on;
    semilogy(f_matlab, Pxx_matlab, 'b--', 'LineWidth', 1);
    title('功率谱密度对比');
    xlabel('频率 (Hz)');
    ylabel('功率谱密度');
    legend('自实现pwelch', 'MATLAB pwelch', 'Location', 'best');
    grid on;
    
    % 计算均方误差
    mse = mean((Pxx_my - Pxx_matlab).^2);
    fprintf('均方误差: %.2e\n', mse);
    
    % 找到峰值频率
    [~, idx1] = max(Pxx_my);
    [~, idx2] = max(Pxx_matlab);
    fprintf('自实现pwelch峰值频率: %.1f Hz\n', f_my(idx1));
    fprintf('MATLAB pwelch峰值频率: %.1f Hz\n', f_matlab(idx2));
end

