clear all; close all; clc;

% 参数设置
M = 256;                % 256APSK
bitsPerSymbol = log2(M); % 8 bits/symbol
numSymbols = 1e5;       % 仿真符号数
snrVec = 0:2:30;        % SNR范围 (dB)

% 定义256APSK星座（4环结构：16+32+64+144）
rings = [16, 32, 64, 144];  % 各环的星座点数
radius_ratios = [1.0, 2.2, 3.5, 5.5];  % 各环的半径比例

% 计算归一化因子
total_power = sum(rings .* radius_ratios.^2);
scaling_factor = sqrt(total_power/M);
radius_ratios = radius_ratios / scaling_factor;

% 生成星座点
constellation = [];
symbol_idx = 1;
for ring_idx = 1:length(rings)
    num_points = rings(ring_idx);
    radius = radius_ratios(ring_idx);
    
    % 相位偏移优化（每环旋转π/点数）
    phase_offset = pi / num_points;
    
    for point_idx = 1:num_points
        phase = 2*pi*(point_idx-1)/num_points + phase_offset;
        constellation(symbol_idx) = radius * exp(1j*phase);
        symbol_idx = symbol_idx + 1;
    end
end

% 能量归一化
constellation = constellation / sqrt(mean(abs(constellation).^2));

% 绘制星座图（按环着色）
figure;
colors = ['b', 'g', 'r', 'm'];  % 不同环使用不同颜色
hold on;
symbol_idx = 1;
for ring_idx = 1:length(rings)
    num_points = rings(ring_idx);
    scatter(real(constellation(symbol_idx:symbol_idx+num_points-1)), ...
           imag(constellation(symbol_idx:symbol_idx+num_points-1)), ...
           50, colors(ring_idx), 'filled', ...
           'DisplayName', sprintf('Ring %d (%d points)', ring_idx, num_points));
    symbol_idx = symbol_idx + num_points;
end
title('256APSK Constellation (16+32+64+144)');
xlabel('In-Phase'); ylabel('Quadrature');
grid on; axis equal;
legend('show');
hold off;

% 仿真主循环
ber = zeros(length(snrVec), 1);
ser = zeros(length(snrVec), 1);

% 生成随机比特流
bits = randi([0 1], numSymbols * bitsPerSymbol, 1);

% 调制（比特 → 符号）
symbols = zeros(numSymbols, 1);
for k = 1:numSymbols
    bitGroup = bits((k-1)*bitsPerSymbol + 1 : k*bitsPerSymbol);%从比特流中提取当前符号对应的8个比特
    symbolIdx = bi2de(bitGroup', 'left-msb') + 1;%将8比特二进制数转换为十进制索引
    symbols(k) = constellation(symbolIdx);%根据索引从星座图中获取对应的复数符号
end

for snrIdx = 1:length(snrVec)
    % AWGN信道
    rxSig = awgn(symbols, snrVec(snrIdx), 'measured');

    % 解调（符号 → 比特）
    rxBits = zeros(numSymbols * bitsPerSymbol, 1);
    rxSymbols = zeros(numSymbols, 1);

    for k = 1:numSymbols
        [~, idx] = min(abs(rxSig(k) - constellation));%计算当前接收符号与所有星座点的复数差值
        rxSymbols(k) = constellation(idx);%将判决后的星座点存入解调符号数组
        bitGroup = de2bi(idx-1, bitsPerSymbol, 'left-msb')';%将星座点索引转换为对应的比特组
        rxBits((k-1)*bitsPerSymbol + 1 : k*bitsPerSymbol) = bitGroup;
    end

    % 计算BER/SER
    ber(snrIdx) = sum(bits ~= rxBits) / (numSymbols * bitsPerSymbol);
    ser(snrIdx) = sum(symbols ~= rxSymbols) / numSymbols;
end

% 绘制性能曲线
figure;
semilogy(snrVec, ber, 'b-o', 'LineWidth', 2); hold on;
semilogy(snrVec, ser, 'r-s', 'LineWidth', 2);
grid on;
xlabel('SNR (dB)');
ylabel('Error Rate');
legend('BER', 'SER', 'Location', 'best');
title('256APSK (16+32+64+144) Performance in AWGN Channel');
ylim([1e-6 1]);

% 显示星座特性
fprintf('星座特性分析:\n');
fprintf('总符号数: %d\n', M);
fprintf('各环配置:\n');
symbol_idx = 1;
for ring_idx = 1:length(rings)
    num_points = rings(ring_idx);
    radius = mean(abs(constellation(symbol_idx:symbol_idx+num_points-1)));
    fprintf(' 环%d: %d点, 半径=%.4f, 功率=%.4f\n', ...
            ring_idx, num_points, radius, radius^2);
    symbol_idx = symbol_idx + num_points;
end
fprintf('平均功率: %.6f\n', mean(abs(constellation).^2));
fprintf('PAPR: %.2f dB\n', 10*log10(max(abs(constellation).^2)/mean(abs(constellation).^2)));