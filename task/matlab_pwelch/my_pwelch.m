function [Pxx, f] = my_pwelch(x, window, noverlap, nfft, fs)
% MY_PWELCH - 实现MATLAB pwelch函数的功能
% 输入参数:
%   x - 输入信号向量
%   window - 窗函数长度或窗函数向量（可选，默认为汉明窗）
%   noverlap - 重叠样本数（可选，默认为窗长的50%）
%   nfft - FFT点数（可选，默认为窗长）
%   fs - 采样频率（可选，默认为1）
% 输出参数:
%   Pxx - 功率谱密度估计
%   f - 对应的频率向量


% 确保x是列向量
x = x(:);
N = length(x);

% 处理window参数
if nargin < 2 || isempty(window)
    % 默认窗长为信号长度的1/8，至少256点
    L = max(256, floor(N/8));
    window = hamming(L);
elseif isscalar(window) %是一个标量
    L = window;
    window = hamming(L);
else
    L = length(window);
    window = window(:);
end

% 处理noverlap参数
if nargin < 3 || isempty(noverlap)
    noverlap = floor(L/2);  % 默认50%重叠
end

% 处理nfft参数
if nargin < 4 || isempty(nfft)
    nfft = L;  % 默认为窗长
end

% 处理fs参数
if nargin < 5 || isempty(fs)
    fs = 1;  % 默认采样频率为1
end


% 计算窗函数的功率
% S1 = sum(window);           % 窗函数幅度和
S2 = sum(window.^2);        % 窗函数功率和

% 计算分段参数
step = L - noverlap;        % 每段之间的步长
num_segments = floor((N - noverlap) / step);  % 总段数


% 初始化功率谱密度累加器
Pxx_sum = zeros(nfft, 1);

% 对每个段进行处理
for i = 1:num_segments
    % 提取当前段
    start_idx = (i-1) * step + 1;
    end_idx = start_idx + L - 1;
    
    if end_idx > N
        break;  % 超出信号长度
    end
    
    segment = x(start_idx:end_idx);
    
    % 应用窗函数
    windowed_segment = segment .* window;
    
    % 零填充到nfft长度
    if length(windowed_segment) < nfft
        windowed_segment = [windowed_segment; zeros(nfft - length(windowed_segment), 1)];
    end
    
    % 计算FFT
    X = fft(windowed_segment, nfft);
    
    % 计算功率谱（幅度平方）
    Pxx_segment = abs(X).^2;
    
    % 累加
    Pxx_sum = Pxx_sum + Pxx_segment;
end

% 计算平均功率谱密度
Pxx = Pxx_sum / num_segments;

% 归一化处理
% 除以采样频率和窗函数功率和进行归一化
Pxx = Pxx / (fs * S2);

% 对于实信号，除了DC和Nyquist分量，其他分量需要乘以2
if isreal(x)
    % 确定单边谱的长度
    if rem(nfft, 2) == 0  % nfft为偶数
        Pxx(2:nfft/2) = 2 * Pxx(2:nfft/2);
        Pxx = Pxx(1:nfft/2+1);
    else  % nfft为奇数
        Pxx(2:(nfft+1)/2) = 2 * Pxx(2:(nfft+1)/2);
        Pxx = Pxx(1:(nfft+1)/2);
    end
end

% 生成对应的频率向量
if isreal(x)
    f = (0:length(Pxx)-1)' * fs / nfft;
else
    f = (0:nfft-1)' * fs / nfft;
end

end