% 演示不同参数的影响
function demo_parameters()
    % 生成测试信号
    fs = 1000;
    t = 0:1/fs:2-1/fs;
    x = sin(2*pi*50*t) + 0.5*sin(2*pi*120*t) + 0.1*randn(size(t));
    
    figure;
    
    % 不同窗长的影响
    subplot(2,2,1);
    [Pxx1, f1] = my_pwelch(x, 128, [], [], fs);
    [Pxx2, f2] = my_pwelch(x, 256, [], [], fs);
    [Pxx3, f3] = my_pwelch(x, 512, [], [], fs);
    
    semilogy(f1, Pxx1, 'r-', f2, Pxx2, 'g-', f3, Pxx3, 'b-');
    title('不同窗长的影响');
    xlabel('频率 (Hz)');
    ylabel('PSD');
    legend('128点', '256点', '512点');
    grid on;
    
    % 不同重叠率的影响
    subplot(2,2,2);
    L = 256;
    [Pxx1, f1] = my_pwelch(x, L, 0, [], fs);      % 无重叠
    [Pxx2, f2] = my_pwelch(x, L, L/4, [], fs);    % 25%重叠
    [Pxx3, f3] = my_pwelch(x, L, L/2, [], fs);    % 50%重叠
    [Pxx4, f4] = my_pwelch(x, L, 3*L/4, [], fs);  % 75%重叠
    
    semilogy(f1, Pxx1, 'r-', f2, Pxx2, 'g-', f3, Pxx3, 'b-', f4, Pxx4, 'm-');
    title('不同重叠率的影响');
    xlabel('频率 (Hz)');
    ylabel('PSD');
    legend('0%', '25%', '50%', '75%');
    grid on;
    
    % 不同窗函数的影响
    subplot(2,2,3);
    L = 256;
    [Pxx1, f1] = my_pwelch(x, hamming(L), [], [], fs);
    [Pxx2, f2] = my_pwelch(x, hanning(L), [], [], fs);
    [Pxx3, f3] = my_pwelch(x, bartlett(L), [], [], fs);
    [Pxx4, f4] = my_pwelch(x, blackman(L), [], [], fs);
    
    semilogy(f1, Pxx1, 'r-', f2, Pxx2, 'g-', f3, Pxx3, 'b-', f4, Pxx4, 'm-');
    title('不同窗函数的影响');
    xlabel('频率 (Hz)');
    ylabel('PSD');
    legend('Hamming', 'Hanning', 'Bartlett', 'Blackman');
    grid on;
    
    % 不同NFFT的影响
    subplot(2,2,4);
    L = 256;
    [Pxx1, f1] = my_pwelch(x, L, [], 256, fs);
    [Pxx2, f2] = my_pwelch(x, L, [], 512, fs);
    [Pxx3, f3] = my_pwelch(x, L, [], 1024, fs);
    
    semilogy(f1, Pxx1, 'r-', f2, Pxx2, 'g-', f3, Pxx3, 'b-');
    title('不同NFFT的影响');
    xlabel('频率 (Hz)');
    ylabel('PSD');
    legend('256点', '512点', '1024点');
    grid on;
end