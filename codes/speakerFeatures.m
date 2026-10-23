function spk = speakerFeatures(cleanSignal, staticMFCC, fs)
%SPEAKERFEATURES  Phase 4 - the fix for defect D3.  [Arnob]
%
% Text-INDEPENDENT vocal-identity descriptors.
%
%   1. F0. Set by vocal-fold mass and length. The strongest low-cost speaker
%      cue and fully available at 8 kHz, since speech F0 lies in 70-350 Hz.
%   2. Cepstral mean. The long-term average spectrum, shaped by vocal tract
%      length and habitual articulation. Note that CMVN deliberately
%      SUBTRACTS this before content matching, so it is information the DTW
%      stage throws away and which is recovered here.
%   3. Spectral tilt. Correlates with glottal source characteristics.
%
% None of these depend on which words were spoken, so an impostor cannot
% defeat them by learning to pronounce the target's name.
%
% LIMITATION TO STATE IN THE REPORT: F0 plus cepstral mean will not reliably
% separate two speakers of the same sex with similar vocal tract length. It
% is a strong additional constraint, not a complete biometric. With ~25
% enrolled speakers you will find pairs it cannot split. Saying so is a
% better answer than overclaiming; the principled next step is GMM-UBM or
% i-vector modelling, which is outside the EEE 312 syllabus.

spk = struct('F0Median', NaN, 'F0IQR', NaN, 'VoicedRatio', 0, ...
             'CepMean', [], 'SpectralTilt', NaN, 'Valid', false);

x = double(cleanSignal(:));
if numel(x) < round(0.10 * fs), return; end

f0Min = 70; f0Max = 350;
lagMin = max(2, floor(fs / f0Max));
lagMax = min(numel(x) - 1, ceil(fs / f0Min));

frameLen = round(0.040 * fs);       % >= 3 pitch periods at 70 Hz
hopLen   = round(0.010 * fs);
if numel(x) < frameLen || lagMax <= lagMin, return; end

nFr = floor((numel(x) - frameLen) / hopLen) + 1;
f0  = nan(nFr, 1);

rms = zeros(nFr, 1);
for k = 1:nFr
    rms(k) = sqrt(mean(x((k-1)*hopLen + (1:frameLen)).^2));
end
gate = 0.15 * max(rms);

for k = 1:nFr
    if rms(k) < gate, continue; end

    seg = x((k-1)*hopLen + (1:frameLen));
    seg = seg - mean(seg);

    % Centre clipping suppresses formant structure and sharpens the pitch
    % peak (Rabiner & Schafer, Ch. 6).
    clipLevel = 0.30 * max(abs(seg));
    sc = seg;
    sc(abs(seg) < clipLevel) = 0;

    r = vsUtils('autocorr', sc, lagMax);
    if r(1) <= 0, continue; end
    r = r / r(1);

    [pk, lag] = max(r(lagMin+1 : lagMax+1));
    lag = lag + lagMin - 1;

    if pk > 0.30
        f0(k) = fs / lag;
    end
end

voiced = f0(~isnan(f0));
spk.VoicedRatio = numel(voiced) / max(nFr, 1);

if numel(voiced) >= 5
    spk.F0Median = median(voiced);
    q = vsUtils('prctile', voiced, [25 75]);
    spk.F0IQR = q(2) - q(1);
end

staticMFCC = orientFeatures(staticMFCC);
if ~isempty(staticMFCC)
    spk.CepMean = mean(staticMFCC, 1);
end

NFFT = 2048;
P   = abs(fft(x .* vsUtils('hamming', numel(x), false), NFFT)).^2;
P   = P(1:NFFT/2+1);
fAx = (0:NFFT/2).' * (fs / NFFT);
b   = (fAx >= 200) & (fAx <= 3500);
if nnz(b) > 10
    cf = polyfit(fAx(b)/1000, 10*log10(P(b) + eps), 1);
    spk.SpectralTilt = cf(1);
end

spk.Valid = ~isnan(spk.F0Median) && ~isempty(spk.CepMean);
end
