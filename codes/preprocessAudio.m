function [frames, preemphSignal, cleanSignal, fs, params] = preprocessAudio(inputAudio, inFs, cfg)
%PREPROCESSAUDIO  Phase 1 - Modification 1.  [Fariha]
%
% Standardisation, VAD trimming, first-order pre-emphasis, Hamming framing.
%
%   Pre-emphasis:  y[n] = x[n] - alpha*x[n-1],  H(z) = 1 - alpha*z^-1
%   Framing:       25 ms frames, 50% overlap, Hamming window
%
% Unchanged from the original implementation apart from the local hamming
% and resample helpers. Phases 1 and 2 were verified correct: an independent
% reimplementation reproduced the stored frame counts exactly (111, 212, 65,
% 323 for the four enrolment files).
%
% Recognition features use the standard 8 kHz resampled signal.

if nargin < 3 || isempty(cfg), cfg = vsConfig(); end

if ischar(inputAudio) || isstring(inputAudio)
    [rawAudio, inFs] = audioread(char(inputAudio));
else
    rawAudio = inputAudio;
end

targetFs = cfg.TargetFs;
alpha    = cfg.PreEmphasisCoeff;

% ---- mono, double, DC-free ----
if size(rawAudio, 2) > 1
    mono = mean(double(rawAudio), 2);
else
    mono = double(rawAudio(:));
end

if inFs ~= targetFs
    x = vsUtils('resample', mono, targetFs, inFs);
else
    x = mono;
end
x = x - mean(x);

% Apply spectral subtraction ONCE. The initial ambient PSD is preferred
% when valid; otherwise spectralSubtract uses its original quietest-frame
% estimator. Enrollment has no runtime ambient profile and stays unchanged.
noiseMethod = 'disabled';
if isfield(cfg, 'SpectralSubtraction') && cfg.SpectralSubtraction
    noiseMethod = 'quietest-frame estimator';
    if isfield(cfg, 'AmbientNoiseProfile') && ~isempty(cfg.AmbientNoiseProfile)
        r = cfg.AmbientNoiseProfile;
        Nss = round(cfg.SSFrameMs * 1e-3 * targetFs);
        Nss = Nss + mod(Nss, 2);
        if isstruct(r) && isfield(r, 'Power') && isfield(r, 'Fs') && ...
                isfield(r, 'FrameLen') && r.Fs == targetFs && ...
                r.FrameLen == Nss && isequal(size(r.Power), [Nss 1]) && ...
                all(isfinite(r.Power(:))) && all(r.Power(:) >= 0)
            noiseMethod = 'shared 3-second ambient reference';
        end
    end
    x = spectralSubtract(x, targetFs, cfg);
end

rawRMS  = sqrt(mean(x.^2));
rawPeak = max(abs(x));
isSilent = (rawRMS < 0.006 && rawPeak < 0.025);

if isSilent
    % Do not amplify a noise floor into something that looks like speech.
    cleanSignal = x;
else
    if rawPeak > 0
        x = x / rawPeak;
    end
    cleanSignal = trimSilence(x, targetFs, cfg.VadThreshold);
end

frameLen = round(cfg.FrameLengthMs * 1e-3 * targetFs);
if numel(cleanSignal) < frameLen
    cleanSignal = [cleanSignal; zeros(frameLen - numel(cleanSignal), 1)];
end

% ---- pre-emphasis ----
preemphSignal = filter([1, -alpha], 1, cleanSignal);

% ---- overlapping Hamming framing ----
frameStep = round(frameLen * (1 - cfg.OverlapRatio));
total     = numel(preemphSignal);

if total < frameLen
    numFrames = 1;
    padded    = [preemphSignal; zeros(frameLen - total, 1)];
else
    numFrames = floor((total - frameLen) / frameStep) + 1;
    padded    = preemphSignal;
end

w = vsUtils('hamming', frameLen, true);
frames = zeros(numFrames, frameLen);
for i = 1:numFrames
    seg = padded((i-1)*frameStep + (1:frameLen));
    frames(i, :) = (seg .* w).';
end

fs = targetFs;
params = struct('TargetFs', targetFs, 'PreEmphasisCoeff', alpha, ...
                'FrameLengthSamples', frameLen, 'FrameStepSamples', frameStep, ...
                'NumFrames', numFrames, 'IsSilent', isSilent, ...
                'RawRMS', rawRMS, 'RawPeak', rawPeak, ...
                'NoiseMethod', noiseMethod);
end


function y = trimSilence(x, fs, vadThresh)
% Short-time energy VAD with a two-frame guard band on each side.

winLen  = round(0.020 * fs);
winStep = round(0.010 * fs);

if numel(x) <= winLen + winStep
    y = x; return;
end

n = floor((numel(x) - winLen) / winStep) + 1;
e = zeros(n, 1);
for k = 1:n
    seg  = x((k-1)*winStep + (1:winLen));
    e(k) = sum(seg.^2) / winLen;
end

if max(e) > 0
    e = e / max(e);
end

active = find(e > vadThresh);
if isempty(active)
    y = x; return;
end

sf = max(1, active(1) - 2);
ef = min(n, active(end) + 2);
s  = max(1, (sf-1)*winStep + 1);
en = min(numel(x), (ef-1)*winStep + winLen);
y  = x(s:en);
end
