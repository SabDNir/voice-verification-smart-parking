function y = spectralSubtract(x, fs, cfg)
%SPECTRALSUBTRACT  Background-noise removal by power spectral subtraction (Boll, 1979).  [Fariha]
%
%   Part of Phase 1. Applied to the 8 kHz recognition signal only; the
%   microphone capture remains transient and is not saved to disk.
%
%   1. Short-time Fourier transform: 32 ms periodic-Hann frames, 50% overlap
%      (a periodic Hann window at 50% overlap sums to exactly 1, so plain
%      overlap-add reconstructs the signal).
%   2. Noise power spectrum Pn(f): reuse the initial 3-s ambient profile
%      during live verification. When absent or invalid, use the ORIGINAL
%      mean of the quietest 10% of frames (enrollment / offline / fallback).
%      Exactly ONE spectrum is subtracted; the methods are never stacked.
%   3. Gain per bin  G = max( 1 - alpha * Pn / P , beta )
%        alpha = 2    over-subtraction, removes the noise "floor"
%        beta  = 0.02 spectral floor, avoids musical-noise holes
%   4. Y = X * sqrt(G), inverse FFT, overlap-add.
%
%   WHY: the database was recorded with a noise gate (exact digital silence
%   between words) while the live microphone hears the room. In a
%   simulation on the database, room noise at 20 dB SNR cut the genuine
%   voice score from 0.29 to 0.02 (below the gate); with this step it stayed
%   at 0.11. On clean audio the step changes nothing, because the estimated
%   noise spectrum is then close to zero.

if nargin < 3 || isempty(cfg), cfg = vsConfig(); end
x = double(x(:));
L = numel(x);
N = round(cfg.SSFrameMs * 1e-3 * fs);
N = N + mod(N, 2);
H = N / 2;
if L < 4 * N
    y = x; return;                       % too short to estimate any noise
end

w   = 0.5 - 0.5 * cos(2 * pi * (0:N-1).' / N);        % periodic Hann
pad = [zeros(N, 1); x; zeros(N, 1)];
nF  = floor((numel(pad) - N) / H) + 1;
idx = (0:N-1).' + (0:nF-1) * H + 1;                     % [N x nF] sample indices

F = fft(pad(idx) .* w, N, 1);
P = abs(F).^2;

% Reuse the previously computed ambient PSD when available. Profile
% construction validates silence, length, clipping, and STFT compatibility.
useAmbient = false;
if isfield(cfg, 'AmbientNoiseProfile') && ~isempty(cfg.AmbientNoiseProfile)
    r = cfg.AmbientNoiseProfile;
    useAmbient = isstruct(r) && isfield(r, 'Power') && ...
                 isfield(r, 'Fs') && isfield(r, 'FrameLen') && ...
                 r.Fs == fs && r.FrameLen == N && ...
                 isequal(size(r.Power), [N 1]) && ...
                 all(isfinite(r.Power(:))) && all(r.Power(:) >= 0);
end
if useAmbient
    Pn = double(cfg.AmbientNoiseProfile.Power);  % fixed 3-second reference
else
    % Original per-recording noise estimation: unchanged fallback.
    [~, ord] = sort(sum(P, 1));
    q  = ord(1:max(3, round(cfg.SSNoiseFraction * nF)));
    Pn = mean(P(:, q), 2);
end

G  = max(1 - cfg.SSOverSubtraction * Pn ./ max(P, 1e-20), cfg.SSFloor);
yf = real(ifft(F .* sqrt(G), N, 1));

out = zeros(numel(pad), 1);
for k = 1:nF
    out(idx(:, k)) = out(idx(:, k)) + yf(:, k);
end
y = out(N+1 : N+L);
end
