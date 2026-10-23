function [profile, reason] = buildAmbientNoiseProfile(raw, captureFs, cfg)
%BUILDAMBIENTNOISEPROFILE  Validate 3-s silence, make a reusable noise PSD.
%   [profile, reason] = buildAmbientNoiseProfile(raw, captureFs, cfg)
%   Empty profile means INVALID reference: revert to the existing per-utterance
%   quietest-frame noise estimator. Audio/profile exist only in MATLAB RAM.
%
%   Applies the same 32-ms periodic Hann STFT as spectralSubtract.m, AFTER
%   converting the reference to the standard 8-kHz recognition sample rate.
%   A mean power spectrum is computed once and reused for all three utterances.
if nargin < 3 || isempty(cfg), cfg = vsConfig(); end
profile = [];
reason = '';
if ~isnumeric(raw) || isempty(raw) || ...
        ~isscalar(captureFs) || ~isfinite(captureFs) || captureFs <= 0
    reason = 'No usable microphone samples.';
    return;
end
if size(raw,2) > 1
    x = mean(double(raw), 2);
else
    x = double(raw(:));
end
if any(~isfinite(x))
    reason = 'Non-finite samples in ambient recording.';
    return;
end
duration = numel(x) / captureFs;
if duration < cfg.AmbientNoiseSeconds - 0.25
    reason = sprintf('Ambient recording is too short (%.2f s).', duration);
    return;
end
if mean(abs(x) >= 0.999) > 0.001
    reason = 'Ambient recording is clipped. Reduce microphone volume.';
    return;
end
% Reject missing audio and obviously speech-contaminated references. The
% transient check deliberately requires multiple strong frames (not one click).
rmsValue = sqrt(mean(x.^2));
noiseDb = 20*log10(rmsValue + 1e-12);
if noiseDb < -85
    reason = 'Ambient audio is near digital silence or the mic is unavailable.';
    return;
end
if noiseDb > -20
    reason = sprintf('Ambient level %.1f dBFS is too high; stay silent.', noiseDb);
    return;
end
frameLen = max(1, round(0.020 * captureFs));
nFrames = floor(numel(x) / frameLen);
if nFrames < 40
    reason = 'Not enough ambient frames for a reliable noise estimate.';
    return;
end
a = reshape(x(1:nFrames*frameLen), frameLen, nFrames);
frameDb = 10*log10(mean(a.^2, 1) + 1e-12);
medDb = median(frameDb);
strong = frameDb > max(medDb + 12, -40);
if nnz(strong) >= max(6, ceil(0.05 * nFrames))
    reason = 'Speech or loud transient noise detected during the silent reference.';
    return;
end
% Match preprocessAudio: resample, then remove DC at the analysis rate.
if captureFs ~= cfg.TargetFs
    x = vsUtils('resample', x, cfg.TargetFs, captureFs);
end
x = double(x(:));
x = x - mean(x);
N = round(cfg.SSFrameMs * 1e-3 * cfg.TargetFs);
N = N + mod(N,2);
H = N/2;
if numel(x) < 4*N
    reason = 'Too few resampled ambient samples.';
    return;
end
w = 0.5 - 0.5*cos(2*pi*(0:N-1).' / N);  % periodic Hann
nF = floor((numel(x)-N)/H)+1;
idx = (0:N-1).' + (0:nF-1)*H + 1;
F = fft(x(idx).*w, N, 1);
Pn = mean(abs(F).^2, 2);  % one fixed profile for the complete login
if numel(Pn) ~= N || any(~isfinite(Pn)) || any(Pn < 0)
    reason = 'Unable to construct a valid ambient power spectrum.';
    return;
end
profile = struct('Power', Pn, 'Fs', cfg.TargetFs, 'FrameLen', N, ...
                 'Seconds', duration, 'NoiseDbFS', noiseDb);
end
